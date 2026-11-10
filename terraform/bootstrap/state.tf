# Remote state bucket for the dev environment.
# Locking uses the S3 native lock file (Terraform >= 1.10), so no DynamoDB table is needed.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tfstate" {
  # Accepted risks for a single-person lab state bucket (documented in docs/risk-acceptance.md):
  #checkov:skip=CKV_AWS_145:SSE-S3 (AES256) instead of a customer KMS key; a CMK costs 1 USD/month, 20 % of the lab budget
  #checkov:skip=CKV_AWS_144:No cross-region replication; versioning covers recovery and replication doubles the cost
  #checkov:skip=CKV_AWS_18:No server access logging; CloudTrail data events cover access auditing in week 3
  #checkov:skip=CKV2_AWS_62:No event notifications needed on a state bucket
  bucket = "secure-serverless-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Refuse any request that is not over TLS.
resource "aws_s3_bucket_policy" "tfstate_tls_only" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# Keep 90 days of old state versions, then clean them up.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
