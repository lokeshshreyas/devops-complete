# =============================================================================
# terraform-docker/backend/providers.tf
# =============================================================================
# This is the ONE Terraform config in this entire project that intentionally
# uses LOCAL state, on purpose, forever. Do not add a backend "s3" block here.
#
# Why: this module's only job is to CREATE the S3 bucket + DynamoDB table that
# the main project's remote state would live in. If its own state also lived
# in that same bucket, destroying/recreating the bucket would strand (or
# delete) the very state file describing the bucket - a classic chicken-and-
# egg problem. Real-world Terraform teams solve this the same way: a small,
# separate "bootstrap" config with local state, applied once, rarely touched
# again. See docs/09-remote-terraform-state.md for the full explanation.
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
