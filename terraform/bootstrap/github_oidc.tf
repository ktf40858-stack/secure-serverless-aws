# GitHub Actions authenticates with short-lived OIDC tokens: no AWS keys stored in GitHub.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only the main branch of this one repository can assume the role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "secure-serverless-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}

# Week 1: the pipeline may only read and write the Terraform state.
# Week 2 adds the exact permissions the application needs, nothing more.
data "aws_iam_policy_document" "github_state_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  statement {
    sid       = "ReadWriteState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
}

resource "aws_iam_role_policy" "github_state_access" {
  name   = "terraform-state-access"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_state_access.json
}

# Week 2: permissions to deploy the dev app, scoped to resources named notes-dev*.
locals {
  acct   = data.aws_caller_identity.current.account_id
  prefix = "notes-dev"
}

data "aws_iam_policy_document" "github_deploy_app" {
  statement {
    sid     = "DynamoDbNotesTable"
    actions = ["dynamodb:*"]
    resources = [
      "arn:aws:dynamodb:${var.region}:${local.acct}:table/${local.prefix}*",
    ]
  }

  statement {
    sid       = "LambdaNotesFunctions"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:${var.region}:${local.acct}:function:${local.prefix}*"]
  }

  statement {
    sid     = "LogGroups"
    actions = ["logs:*"]
    resources = [
      "arn:aws:logs:${var.region}:${local.acct}:log-group:/aws/lambda/${local.prefix}*",
      "arn:aws:logs:${var.region}:${local.acct}:log-group:/aws/apigateway/${local.prefix}*",
    ]
  }

  statement {
    sid       = "DescribeLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid       = "HttpApi"
    actions   = ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE", "apigateway:TagResource"]
    resources = ["arn:aws:apigateway:${var.region}::/apis", "arn:aws:apigateway:${var.region}::/apis/*", "arn:aws:apigateway:${var.region}::/tags/*"]
  }

  statement {
    sid = "CreateAppRolesWithBoundary"
    actions = [
      "iam:CreateRole", "iam:PutRolePolicy", "iam:UpdateAssumeRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.acct}:role/${local.prefix}*"]

    # Anti privilege escalation: any role the pipeline creates or edits must carry the boundary.
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.app_boundary.arn]
    }
  }

  # Read-only and delete actions do not accept the boundary condition key.
  statement {
    sid = "AppRolesReadDelete"
    actions = [
      "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:DeleteRole", "iam:DeleteRolePolicy", "iam:TagRole", "iam:UntagRole",
    ]
    resources = ["arn:aws:iam::${local.acct}:role/${local.prefix}*"]
  }

  statement {
    sid       = "ReadBoundary"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = [aws_iam_policy.app_boundary.arn]
  }

  # The pipeline can hand app roles to Lambda only, never to any other service.
  statement {
    sid       = "PassAppRolesToLambda"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.acct}:role/${local.prefix}*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadIdentity"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy_app" {
  name   = "deploy-notes-dev"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy_app.json
}

# Ceiling for every application role: even a bad inline policy cannot go beyond this.
data "aws_iam_policy_document" "app_boundary" {
  statement {
    sid       = "AppLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${local.acct}:log-group:/aws/lambda/${local.prefix}*:*"]
  }

  statement {
    sid       = "AppTables"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:Scan", "dynamodb:Query"]
    resources = ["arn:aws:dynamodb:${var.region}:${local.acct}:table/${local.prefix}*"]
  }

  statement {
    #checkov:skip=CKV_AWS_111:X-Ray has no resource-level permissions, so "*" is the only option
    sid       = "Tracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "app_boundary" {
  name        = "${local.prefix}-boundary"
  description = "Permissions boundary for roles created by the deploy pipeline"
  policy      = data.aws_iam_policy_document.app_boundary.json
}

output "app_boundary_arn" {
  value = aws_iam_policy.app_boundary.arn
}
