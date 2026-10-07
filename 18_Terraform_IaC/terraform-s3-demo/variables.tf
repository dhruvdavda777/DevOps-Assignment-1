variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "localstack_endpoint" {
  description = "LocalStack edge endpoint"
  type        = string
  default     = "http://localhost:4566"
}

variable "bucket_name" {
  description = "Name of the S3 bucket (must be globally unique on real AWS)"
  type        = string
  default     = "dhruv-24bcs10203-devops-assignment"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket names must be lowercase, 3-63 characters, and start/end alphanumeric."
  }
}

variable "environment" {
  description = "Environment tag applied to every resource"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "enable_versioning" {
  description = "Whether to enable S3 object versioning"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    Owner      = "Dhruv Davda"
    Roll       = "24BCS10203"
    Group      = "A"
    ManagedBy  = "Terraform"
    Assignment = "Session-18"
  }
}

variable "enable_lifecycle_rules" {
  description = <<-EOT
    Create the S3 lifecycle configuration.
    Defaults to false because LocalStack community does not implement the
    lifecycle read-back the AWS provider waits on, which makes apply time out.
    Set to true against real AWS.
  EOT
  type        = bool
  default     = false
}
