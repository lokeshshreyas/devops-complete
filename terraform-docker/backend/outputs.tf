# =============================================================================
# terraform-docker/backend/outputs.tf
# =============================================================================
# Read by ./scripts/advanced/01-setup-backend.sh via `terraform output -raw`
# to write the backend.tf files in terraform-docker/ and terraform-eks/.
# =============================================================================

output "bucket_name" {
  description = "S3 bucket holding Terraform state for this project"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  description = "DynamoDB table used for Terraform state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "region" {
  description = "Region the state bucket + lock table were created in"
  value       = var.aws_region
}
