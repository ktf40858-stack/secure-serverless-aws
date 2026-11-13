# One multi-region trail (the first copy of management events is free).
# Files go to a dedicated, locked-down bucket; a copy goes to CloudWatch Logs for the alarms.

resource "aws_s3_bucket" "trail" {
  #checkov:skip=CKV_AWS_145:SSE-S3 instead of a customer KMS key (1 USD/month, 20 % of the lab budget)
  #checkov:skip=CKV_AWS_144:No cross-region replication for a lab audit bucket
  #checkov:skip=CKV_AWS_18:Access logging of the log bucket itself would need another bucket; CloudTrail already records its API calls
  #checkov:skip=CKV2_AWS_62:No consumer for object notifications
  bucket        = "${local.name}-cloudtrail-${local.acct}"
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Only CloudTrail of THIS account and THIS trail may write; TLS only.
data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${var.region}:${local.acct}:trail/${local.name}-trail"]
    }
  }

  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${local.acct}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${var.region}:${local.acct}:trail/${local.name}-trail"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
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

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

resource "aws_cloudwatch_log_group" "trail" {
  #checkov:skip=CKV_AWS_158:AWS managed encryption for log groups; a customer KMS key is out of the lab budget
  #checkov:skip=CKV_AWS_338:30 days in CloudWatch for alarms; the S3 copy keeps 90 days
  name              = "/aws/cloudtrail/${local.name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "trail_to_cw_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.acct]
    }
  }
}

resource "aws_iam_role" "trail_to_cw" {
  name               = "${local.name}-cloudtrail-to-logs"
  assume_role_policy = data.aws_iam_policy_document.trail_to_cw_trust.json
}

resource "aws_iam_role_policy" "trail_to_cw" {
  name = "write-trail-log-group"
  role = aws_iam_role.trail_to_cw.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "main" {
  #checkov:skip=CKV_AWS_35:SSE-S3 instead of a KMS CMK (budget); integrity is covered by log file validation
  #checkov:skip=CKV_AWS_252:No SNS notification per log file; alerts come from metric filters and EventBridge
  name                          = "${local.name}-trail"
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true # tamper evidence: signed digest files every hour
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_to_cw.arn

  # Management events (free first copy) + object-level access to the Terraform state only.
  advanced_event_selector {
    name = "Management events"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  advanced_event_selector {
    name = "Terraform state object access"
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
    field_selector {
      field       = "resources.ARN"
      starts_with = ["arn:${data.aws_partition.current.partition}:s3:::${var.state_bucket}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.trail]
}

# CIS: Block Public Access at the account level, on top of every bucket's own setting.
resource "aws_s3_account_public_access_block" "account" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
