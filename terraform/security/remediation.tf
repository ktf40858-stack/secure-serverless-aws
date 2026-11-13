# EventBridge -> Lambda: S3 Block Public Access is put back within seconds of being weakened.

data "archive_file" "remediate_s3" {
  type        = "zip"
  source_file = "${path.module}/../../app/remediation/src/remediate_s3.py"
  output_path = "${path.module}/build/remediate_s3.zip"
}

resource "aws_cloudwatch_log_group" "remediate_s3" {
  #checkov:skip=CKV_AWS_158:AWS managed encryption for log groups; a customer KMS key is out of the lab budget
  #checkov:skip=CKV_AWS_338:30 days of retention is enough for a lab
  name              = "/aws/lambda/${local.name}-remediate-s3"
  retention_in_days = 30
}

data "aws_iam_policy_document" "remediate_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.acct]
    }
  }
}

resource "aws_iam_role" "remediate_s3" {
  name               = "${local.name}-remediate-s3"
  assume_role_policy = data.aws_iam_policy_document.remediate_trust.json
}

# Least privilege: read and set Block Public Access, publish one alert, write its own logs.
# It cannot read objects, change bucket policies or delete anything.
data "aws_iam_policy_document" "remediate_s3" {
  statement {
    sid       = "BucketPublicAccessBlock"
    actions   = ["s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::*"]
  }

  statement {
    #checkov:skip=CKV_AWS_111:account-level Block Public Access has no resource ARN
    #checkov:skip=CKV_AWS_356:account-level Block Public Access has no resource ARN
    sid       = "AccountPublicAccessBlock"
    actions   = ["s3:GetAccountPublicAccessBlock", "s3:PutAccountPublicAccessBlock"]
    resources = ["*"]
  }

  statement {
    sid       = "Alert"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid       = "OwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.remediate_s3.arn}:*"]
  }
}

resource "aws_iam_role_policy" "remediate_s3" {
  name   = "remediate-s3-public-access"
  role   = aws_iam_role.remediate_s3.id
  policy = data.aws_iam_policy_document.remediate_s3.json
}

resource "aws_lambda_function" "remediate_s3" {
  #checkov:skip=CKV_AWS_117:No VPC; the function only calls S3 and SNS APIs, a VPC would need a NAT gateway
  #checkov:skip=CKV_AWS_116:EventBridge retries failed invocations (2 attempts) and the errors alarm fires
  #checkov:skip=CKV_AWS_272:Code signing is a planned improvement
  #checkov:skip=CKV_AWS_173:Environment holds only the topic ARN, no secret
  #checkov:skip=CKV_AWS_115:Reserved concurrency impossible on a new account (quota 10); events are rare
  function_name    = "${local.name}-remediate-s3"
  role             = aws_iam_role.remediate_s3.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "remediate_s3.lambda_handler"
  filename         = data.archive_file.remediate_s3.output_path
  source_code_hash = data.archive_file.remediate_s3.output_base64sha256
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      ALERT_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.remediate_s3.name
  }

  depends_on = [aws_iam_role_policy.remediate_s3]
}

resource "aws_cloudwatch_event_rule" "s3_public_access" {
  name = "${local.name}-s3-public-access-changed"
  # Names are the CloudTrail event names, which differ from the API names: the API call
  # DeletePublicAccessBlock is logged as DeleteBucketPublicAccessBlock (found during the live test).
  description = "Any change that could make a bucket or the account public"
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName = [
        "PutBucketPolicy", "PutBucketAcl", "PutBucketPublicAccessBlock", "DeleteBucketPublicAccessBlock",
        "PutAccountPublicAccessBlock", "DeleteAccountPublicAccessBlock",
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "s3_public_access" {
  rule = aws_cloudwatch_event_rule.s3_public_access.name
  arn  = aws_lambda_function.remediate_s3.arn

  retry_policy {
    maximum_retry_attempts       = 2
    maximum_event_age_in_seconds = 600
  }
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowFromEventBridgeRule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate_s3.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_public_access.arn
}
