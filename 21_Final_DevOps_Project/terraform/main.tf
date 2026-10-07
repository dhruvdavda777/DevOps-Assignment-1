# Infrastructure for the final project: an S3 bucket holding build artifacts.
# Runs against LocalStack, as in Sessions 18-19.
# Dhruv Davda - 24BCS10203
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region                      = "ap-south-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true
  endpoints { s3 = "http://localhost:4566" }
  default_tags {
    tags = { Owner = "Dhruv Davda", Roll = "24BCS10203", Project = "taskboard" }
  }
}

variable "bucket_name" {
  type    = string
  default = "dhruv-taskboard-artifacts"
}

resource "aws_s3_bucket" "artifacts" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "artifacts_bucket" { value = aws_s3_bucket.artifacts.id }
output "versioning" { value = aws_s3_bucket_versioning.artifacts.versioning_configuration[0].status }
