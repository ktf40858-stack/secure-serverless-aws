data "archive_file" "api" {
  type        = "zip"
  source_file = "${path.module}/../../../app/api/src/handler.py"
  output_path = "${path.module}/build/api.zip"
}

resource "aws_cloudwatch_log_group" "api" {
  #checkov:skip=CKV_AWS_158:AWS managed encryption for log groups; a customer KMS key is out of the lab budget
  #checkov:skip=CKV_AWS_338:30 days of retention is enough for a lab and keeps cost near zero
  name              = "/aws/lambda/${local.name}-api"
  retention_in_days = var.log_retention_days
}

# Least privilege: this role can only write its own logs and touch the notes table.
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "api" {
  name                 = "${local.name}-api"
  assume_role_policy   = data.aws_iam_policy_document.lambda_trust.json
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/notes-dev-boundary"
}

data "aws_iam_policy_document" "api" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.api.arn}:*"]
  }

  statement {
    sid = "NotesTableOnly"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query", # list = Query on the caller's partition; Scan is no longer allowed
    ]
    resources = [aws_dynamodb_table.notes.arn]
  }

  statement {
    sid       = "Tracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"] # X-Ray does not support resource-level permissions
  }
}

resource "aws_iam_role_policy" "api" {
  name   = "${local.name}-api"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api.json
}

resource "aws_lambda_function" "api" {
  #checkov:skip=CKV_AWS_117:No VPC; the function only calls DynamoDB and a VPC would need a NAT gateway (about 32 USD/month)
  #checkov:skip=CKV_AWS_116:Synchronous API calls; failures go back to the caller, so a DLQ has nothing to catch
  #checkov:skip=CKV_AWS_272:Code signing is planned as a later improvement; the pipeline is the only deploy path
  #checkov:skip=CKV_AWS_173:Environment holds only the table name, no secret; AWS managed encryption is enough
  function_name                  = "${local.name}-api"
  role                           = aws_iam_role.api.arn
  runtime                        = "python3.13"
  architectures                  = ["arm64"]
  handler                        = "handler.lambda_handler"
  filename                       = data.archive_file.api.output_path
  source_code_hash               = data.archive_file.api.output_base64sha256
  memory_size                    = 128
  timeout                        = 5
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.notes.name
      LOG_LEVEL  = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.api.name
  }

  depends_on = [aws_iam_role_policy.api]
}
