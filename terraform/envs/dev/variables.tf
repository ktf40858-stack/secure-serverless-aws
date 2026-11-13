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
  description = <<-EOT
    Hard cap on concurrent Lambda executions (cost and abuse guardrail).
    -1 = no reservation. New AWS accounts have a total concurrency quota of 10 and AWS refuses
    any reservation that leaves fewer than 10 unreserved, so -1 is the only value that works
    until the quota is raised. The cap then comes from the account quota (10) and the API
    Gateway throttling (api_rate_limit / api_burst_limit). Set to 5 once the quota is 1000.
  EOT
  type        = number
  default     = -1
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
