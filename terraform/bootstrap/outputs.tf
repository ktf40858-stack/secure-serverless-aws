output "state_bucket" {
  description = "Bucket to put in the dev backend configuration"
  value       = aws_s3_bucket.tfstate.bucket
}

output "github_deploy_role_arn" {
  description = "Role ARN to set as the AWS_ROLE_ARN GitHub secret"
  value       = aws_iam_role.github_deploy.arn
}
