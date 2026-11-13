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

variable "github_oidc_subject_repo" {
  description = <<-EOT
    Repository part of the GitHub OIDC `sub` claim. This repository uses GitHub's immutable subject
    format, owner@owner_id/name@repo_id, so a deleted-then-recreated or renamed repo with the same
    name cannot reuse the trust. Read it with:
    gh api repos/OWNER/REPO/actions/oidc/customization/sub  (field sub_claim_prefix, without "repo:")
  EOT
  type        = string
  default     = "ktf40858-stack@228718303/secure-serverless-aws@1452096294"
}
