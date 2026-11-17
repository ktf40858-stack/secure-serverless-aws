# Week 4, found with Stratus Red Team (aws.exfiltration.s3-backdoor-bucket-policy): a bucket policy
# that grants another AWS account access is not "public", so the S3 auto-remediation did nothing.
# First idea: forward IAM Access Analyzer findings to the alert topic. Tested live: the analyzer
# scanned the backdoored bucket but raised NO finding after 35 minutes, so this rule did not catch
# that attack. It is kept as an extra layer for the other resource types the analyzer covers
# (IAM roles, KMS, Lambda, SQS, secrets...). The attack itself is caught by the CIS 4.8 alarm
# "s3-bucket-policy-changes" in alerts.tf.

resource "aws_cloudwatch_event_rule" "external_access" {
  name        = "${local.name}-external-access"
  description = "IAM Access Analyzer found a resource shared outside the account"
  event_pattern = jsonencode({
    source        = ["aws.access-analyzer"]
    "detail-type" = ["Access Analyzer Finding"]
    detail = {
      status = ["ACTIVE"]
    }
  })
}

resource "aws_cloudwatch_event_target" "external_access" {
  rule      = aws_cloudwatch_event_rule.external_access.name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      type      = "$.detail.resourceType"
      resource  = "$.detail.resource"
      principal = "$.detail.principal"
      public    = "$.detail.isPublic"
      time      = "$.time"
    }
    input_template = "\"EXTERNAL ACCESS at <time>: <type> <resource> is reachable from outside the account (public=<public>, principal=<principal>). If this was not intended, remove the policy statement and archive the finding.\""
  }
}

# EventBridge needs explicit permission to publish. The first statement keeps the default
# owner access that the CloudWatch alarms and the remediation Lambda rely on.
data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid = "AccountOwner"
    actions = [
      "SNS:Publish", "SNS:Subscribe", "SNS:Receive", "SNS:GetTopicAttributes", "SNS:SetTopicAttributes",
      "SNS:ListSubscriptionsByTopic", "SNS:AddPermission", "SNS:RemovePermission", "SNS:DeleteTopic",
    ]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [local.acct]
    }
  }

  statement {
    sid       = "CloudWatchAlarms"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.acct]
    }
  }

  statement {
    sid       = "EventBridgeExternalAccess"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.external_access.arn]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}
