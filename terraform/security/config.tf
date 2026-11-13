# AWS Config + CIS AWS Foundations v1.4 Level 1 conformance pack (official AWS sample template,
# conformance/cis-aws-v1.4-level1.yaml: 26 managed rules + 18 manual process checks, no custom code).
#
# Pay-per-use, so it is behind a switch: turned on for a few days to measure the CIS score before
# and after the fixes, then turned off (enable_config = false destroys all of it).

variable "enable_config" {
  description = "Turn AWS Config and the CIS conformance pack on (true) or off (false)"
  type        = bool
  default     = false
}

resource "aws_iam_service_linked_role" "config" {
  count            = var.enable_config ? 1 : 0
  aws_service_name = "config.amazonaws.com"
}

resource "aws_s3_bucket" "config" {
  #checkov:skip=CKV_AWS_145:SSE-S3; temporary bucket for a few days of Config snapshots
  #checkov:skip=CKV_AWS_144:No replication for a temporary bucket
  #checkov:skip=CKV_AWS_18:CloudTrail records its API calls
  #checkov:skip=CKV2_AWS_62:No consumer for notifications
  #checkov:skip=CKV2_AWS_61:Lifecycle not needed, the bucket is destroyed with force_destroy when Config is turned off
  count         = var.enable_config ? 1 : 0
  bucket        = "${local.name}-config-${local.acct}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "config" {
  count  = var.enable_config ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  count  = var.enable_config ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  count                   = var.enable_config ? 1 : 0
  bucket                  = aws_s3_bucket.config[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "config_bucket" {
  count = var.enable_config ? 1 : 0

  statement {
    sid       = "ConfigAclCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config[0].arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [local.acct]
    }
  }

  statement {
    sid       = "ConfigWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config[0].arn}/AWSLogs/${local.acct}/Config/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [local.acct]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.config[0].arn, "${aws_s3_bucket.config[0].arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  count  = var.enable_config ? 1 : 0
  bucket = aws_s3_bucket.config[0].id
  policy = data.aws_iam_policy_document.config_bucket[0].json
}

resource "aws_config_configuration_recorder" "main" {
  count    = var.enable_config ? 1 : 0
  name     = "${local.name}-recorder"
  role_arn = aws_iam_service_linked_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true # IAM users, roles and policies (needed by the CIS IAM rules)
  }
}

resource "aws_config_delivery_channel" "main" {
  count          = var.enable_config ? 1 : 0
  name           = "${local.name}-delivery"
  s3_bucket_name = aws_s3_bucket.config[0].id

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.main, aws_s3_bucket_policy.config]
}

resource "aws_config_configuration_recorder_status" "main" {
  count      = var.enable_config ? 1 : 0
  name       = aws_config_configuration_recorder.main[0].name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_config_conformance_pack" "cis" {
  count         = var.enable_config ? 1 : 0
  name          = "cis-aws-v1-4-level1"
  template_body = file("${path.module}/conformance/cis-aws-v1.4-level1.yaml")
  depends_on    = [aws_config_configuration_recorder_status.main]
}
