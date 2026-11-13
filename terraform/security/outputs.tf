output "alert_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "trail_bucket" {
  value = aws_s3_bucket.trail.id
}

output "remediation_function" {
  value = aws_lambda_function.remediate_s3.function_name
}
