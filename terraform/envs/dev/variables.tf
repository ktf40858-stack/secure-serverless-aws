variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "log_retention_days" {
  description = "CloudWatch log retention"
  type        = number
  default     = 30
}

variable "lambda_reserved_concurrency" {
  description = "Hard cap on concurrent Lambda executions (cost and abuse guardrail)"
  type        = number
  default     = 5
}

variable "api_rate_limit" {
  description = "Steady-state requests per second allowed by API Gateway"
  type        = number
  default     = 10
}

variable "api_burst_limit" {
  description = "Burst requests allowed by API Gateway"
  type        = number
  default     = 20
}
