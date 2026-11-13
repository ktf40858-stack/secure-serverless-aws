# Account security baseline: audit trail, alerts, auto-remediation.
#
# Separate Terraform root on purpose (separation of duties): it is applied by the account admin,
# NOT by the app pipeline. The GitHub deploy role has no permission on CloudTrail, EventBridge or
# SNS, so a compromised pipeline cannot switch off the logging that would catch it.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # bucket comes from `terraform init -backend-config=backend.hcl` (same state bucket, own key)
  backend "s3" {
    key          = "security/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "secure-serverless-aws"
      Environment = "security"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  acct = data.aws_caller_identity.current.account_id
  name = "secbaseline"
}
