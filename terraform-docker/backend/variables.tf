# =============================================================================
# terraform-docker/backend/variables.tf
# =============================================================================

variable "aws_region" {
  description = "AWS region to create the state bucket + lock table in. Should match the region you deploy terraform-docker/ and terraform-eks/ into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to build the bucket/table names, e.g. 'thermos'."
  type        = string
  default     = "thermos"
}
