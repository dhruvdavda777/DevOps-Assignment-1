variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "project" {
  type    = string
  default = "dhruv-s19"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "az" {
  type    = string
  default = "ap-south-1a"
}

variable "instance_count" {
  type    = number
  default = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 5
    error_message = "instance_count must be between 1 and 5."
  }
}

variable "common_tags" {
  type = map(string)
  default = {
    Owner      = "Dhruv Davda"
    Roll       = "24BCS10203"
    Group      = "A"
    ManagedBy  = "Terraform"
    Assignment = "Session-19"
  }
}
