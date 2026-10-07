# Session 19 - end-to-end infrastructure.
# Runs against LocalStack; see the README for why.
# Dhruv Davda - 24BCS10203
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = var.endpoint
    ec2 = var.endpoint
    iam = var.endpoint
    sts = var.endpoint
  }

  default_tags {
    tags = var.common_tags
  }
}
