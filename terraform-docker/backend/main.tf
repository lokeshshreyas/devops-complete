# =============================================================================
# terraform-docker/backend/main.tf — Remote State Bootstrap
# =============================================================================
# Creates exactly two things, shared by BOTH terraform-docker/ and
# terraform-eks/ (they use the same bucket with different state "key" paths,
# and the same DynamoDB lock table):
#   1. An S3 bucket to hold Terraform state files
#   2. A DynamoDB table to hold state locks
#
# This module is applied by ./scripts/advanced/01-setup-backend.sh — you do
# not need to run terraform commands here by hand. See
# docs/09-remote-terraform-state.md for the full walkthrough.
#
# KodeKloud-specific choices (see docs/03-kodekloud-aws-playground-limits.md):
#   - force_destroy = true on the bucket, so a short-lived lab session can
#     tear this down in one command even if it still has state files in it.
#     (Do NOT do this for a real team's production state bucket.)
#   - PAY_PER_REQUEST billing on the DynamoDB table, so it costs nothing
#     while idle instead of provisioning read/write capacity you pay for
#     whether you use it or not.
# =============================================================================

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "terraform_state" {
  bucket        = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # KodeKloud sessions are short-lived - allow easy teardown

  tags = {
    Project = var.project_name
    Purpose = "terraform-remote-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # free when idle - no provisioned capacity to pay for
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project = var.project_name
    Purpose = "terraform-state-locking"
  }
}
