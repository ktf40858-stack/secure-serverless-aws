# Fixes for the CIS v1.4 Level 1 findings of 2026-11-12 (see docs/cis-score.md). All free.

# CIS 1.8-1.9 (rule iam-password-policy). Values follow the conformance pack parameters.
resource "aws_iam_account_password_policy" "cis" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  password_reuse_prevention      = 24
  max_password_age               = 90
  allow_users_to_change_password = true
}

# CIS 2.2.1 (rule ec2-ebs-encryption-by-default): any future EBS volume is encrypted.
resource "aws_ebs_encryption_by_default" "cis" {
  enabled = true
}

# CIS 1.20 (rule iam-access-analyzer-enabled): flags any resource shared outside the account.
# The external access analyzer is free.
resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "${local.name}-access-analyzer"
  type          = "ACCOUNT"
}

# CIS 1.17 (rule iam-policy-in-use): a role exists to manage incidents with AWS Support.
# Only humans of this account, signed in with MFA, can assume it.
data "aws_iam_policy_document" "support_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.acct}:root"]
    }
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "support" {
  name                 = "${local.name}-aws-support"
  description          = "CIS 1.17: incident handling with AWS Support (MFA required)"
  assume_role_policy   = data.aws_iam_policy_document.support_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "support" {
  role       = aws_iam_role.support.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSSupportAccess"
}
