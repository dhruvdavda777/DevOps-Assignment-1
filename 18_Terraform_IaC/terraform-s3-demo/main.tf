# ---------------------------------------------------------------------------
# S3 bucket + its configuration sub-resources.
#
# In AWS provider v4+ each aspect of a bucket (versioning, encryption, public
# access, lifecycle) is its OWN resource rather than a block inside the bucket.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "assignment" {
  bucket = var.bucket_name

  tags = merge(var.common_tags, {
    Name        = var.bucket_name
    Environment = var.environment
  })
}

# Versioning: keeps every version of an object, so an overwrite or delete is
# recoverable.
resource "aws_s3_bucket_versioning" "assignment" {
  bucket = aws_s3_bucket.assignment.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Server-side encryption at rest, applied to every new object by default.
resource "aws_s3_bucket_server_side_encryption_configuration" "assignment" {
  bucket = aws_s3_bucket.assignment.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block ALL public access. This is the single most important S3 setting -
# public buckets are the classic cloud data-leak headline.
resource "aws_s3_bucket_public_access_block" "assignment" {
  bucket = aws_s3_bucket.assignment.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: move old versions to cheaper storage, then expire them.
resource "aws_s3_bucket_lifecycle_configuration" "assignment" {
  count  = var.enable_lifecycle_rules ? 1 : 0
  bucket = aws_s3_bucket.assignment.id

  # depends_on is required: a lifecycle rule targeting noncurrent versions is
  # only meaningful once versioning exists.
  depends_on = [aws_s3_bucket_versioning.assignment]

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# An object, so the bucket is not empty and `terraform show` has something real.
resource "aws_s3_object" "readme" {
  bucket       = aws_s3_bucket.assignment.id
  key          = "README.txt"
  content_type = "text/plain"
  content      = <<-EOT
    DevOps Assignment - Session 18
    Owner : ${var.common_tags["Owner"]}
    Roll  : ${var.common_tags["Roll"]}
    Env   : ${var.environment}
    Bucket: ${var.bucket_name}
    Created by Terraform.
  EOT

  tags = var.common_tags
}
