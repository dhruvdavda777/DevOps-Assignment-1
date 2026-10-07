# Provider configuration.
#
# NOTE: this project runs against LocalStack (an AWS API emulator running in
# Docker), not against real AWS. The resource definitions are identical to a
# real deployment; only the endpoints and credential handling differ.
# Dhruv Davda - 24BCS10203

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # --- LocalStack settings -------------------------------------------------
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true # LocalStack needs path-style URLs

  endpoints {
    s3  = var.localstack_endpoint
    iam = var.localstack_endpoint
    sts = var.localstack_endpoint
  }
}
