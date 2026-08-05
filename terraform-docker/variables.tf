# =============================================================================
# variables.tf — Input Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region. KodeKloud AWS Playground supports us-east-1, us-west-2, us-east-2."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to tag and name every resource."
  type        = string
  default     = "thermos"
}

variable "instance_type" {
  description = "EC2 instance type. Must be one of the types allowed by the KodeKloud AWS Playground (see docs/03-kodekloud-aws-playground-limits.md)."
  type        = string
  default     = "t3.medium"

  validation {
    condition = contains(
      ["t2.nano", "t2.micro", "t2.small", "t2.medium",
      "t3.nano", "t3.micro", "t3.small", "t3.medium"],
      var.instance_type
    )
    error_message = "instance_type must be one of the KodeKloud-allowed types: t2/t3 nano, micro, small, or medium."
  }
}

variable "allowed_ssh_cidr" {
  description = "CIDR range allowed to SSH into the instance. Defaults to 'anywhere' for workshop convenience - tighten this to your own IP (e.g. \"1.2.3.4/32\") if you want to be stricter."
  type        = string
  default     = "0.0.0.0/0"
}
