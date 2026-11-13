# Alert channel + CIS-style alarms on the CloudTrail log group (8 alarms, inside the 10 free ones).

resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:CloudWatch alarms cannot publish to a topic encrypted with the AWS managed SNS key, and a CMK costs 1 USD/month; alerts carry no secrets
  name = "${local.name}-security-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  # name => { pattern, threshold over 5 minutes, description }
  trail_alarms = {
    root-account-usage = {
      pattern     = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
      threshold   = 1
      description = "CIS: the root user was used. Nobody should use root day to day."
    }
    console-login-without-mfa = {
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
      threshold   = 1
      description = "CIS: an IAM user signed in to the console without MFA."
    }
    console-login-failures = {
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.errorMessage = \"Failed authentication\") }"
      threshold   = 3
      description = "CIS: repeated failed console sign-ins (password guessing)."
    }
    unauthorized-api-calls = {
      pattern     = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
      threshold   = 5
      description = "CIS: burst of AccessDenied calls (someone probing permissions). Threshold 5 to ignore single expected denials."
    }
    iam-policy-changes = {
      pattern     = "{ ($.eventName = DeleteGroupPolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = DeleteUserPolicy) || ($.eventName = PutGroupPolicy) || ($.eventName = PutRolePolicy) || ($.eventName = PutUserPolicy) || ($.eventName = CreatePolicy) || ($.eventName = DeletePolicy) || ($.eventName = CreatePolicyVersion) || ($.eventName = DeletePolicyVersion) || ($.eventName = AttachRolePolicy) || ($.eventName = DetachRolePolicy) || ($.eventName = AttachUserPolicy) || ($.eventName = DetachUserPolicy) || ($.eventName = AttachGroupPolicy) || ($.eventName = DetachGroupPolicy) }"
      threshold   = 1
      description = "CIS: an IAM policy was created, changed or attached. Expected during deploys, suspicious otherwise."
    }
    cloudtrail-changes = {
      pattern     = "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) || ($.eventName = PutEventSelectors) }"
      threshold   = 1
      description = "CIS: the audit trail was changed or stopped (classic first step of an attacker)."
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "trail" {
  for_each       = local.trail_alarms
  name           = "${local.name}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.key
    namespace     = "SecurityBaseline"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "trail" {
  for_each            = local.trail_alarms
  alarm_name          = "${local.name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = "SecurityBaseline"
  metric_name         = each.key
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  depends_on = [aws_cloudwatch_log_metric_filter.trail]
}

# Application health: any error in the notes API or in the remediation function itself.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = {
    notes-api   = "notes-dev-api"
    remediation = aws_lambda_function.remediate_s3.function_name
  }
  alarm_name          = "${local.name}-lambda-errors-${each.key}"
  alarm_description   = "Lambda ${each.value} returned errors."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
