variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email that receives security alerts (the subscription must be confirmed from the inbox)"
  type        = string
}

variable "state_bucket" {
  description = "Terraform state bucket whose object-level access is recorded (CloudTrail data events)"
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the CloudTrail copy in CloudWatch Logs"
  type        = number
  default     = 30
}
