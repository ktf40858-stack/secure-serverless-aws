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

  # Partial configuration: bucket comes from `terraform init -backend-config=backend.hcl`
  backend "s3" {
    key          = "dev/terraform.tfstate"
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
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name = "notes-dev"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
