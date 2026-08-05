# =============================================================================
# backend.tf — Remote State Backend (S3 + DynamoDB) — INACTIVE TEMPLATE
# =============================================================================
# By default this project uses local Terraform state, and the commented-out
# block below is inert - Terraform ignores it. To switch to remote state:
#   1. Run: ./scripts/advanced/01-setup-backend.sh
#      This OVERWRITES this entire file with a real, uncommented backend
#      block pointing at a freshly created S3 bucket + DynamoDB table, and
#      then runs 'terraform init -migrate-state' for you automatically.
#   2. To go back to local state later: run
#      ./scripts/advanced/05-destroy-backend.sh (tears down the bucket/table
#      and deletes this file, restoring this exact template on next init).
# You do not need to hand-edit or uncomment anything yourself - the commented
# block below exists purely as a reference for what 01-setup-backend.sh writes.
# =============================================================================

# terraform {
#   backend "s3" {
#     bucket         = "thermos-terraform-state-<your-account-id>"
#     key            = "terraform-docker/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "thermos-terraform-locks"
#   }
# }
