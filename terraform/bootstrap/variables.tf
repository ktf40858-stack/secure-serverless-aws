variable "region" {
  description = "AWS region for the lab"
  type        = string
  default     = "us-east-1"
}

variable "budget_email" {
  description = "Email that receives the budget alerts (set in terraform.tfvars, never committed)"
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly budget in USD"
  type        = string
  default     = "5"
}

variable "github_repo" {
  description = "GitHub repository allowed to deploy, as owner/name"
  type        = string
  default     = "ktf40858-stack/secure-serverless-aws"
}
