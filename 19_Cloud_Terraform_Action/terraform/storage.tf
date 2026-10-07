# ---------------------------------------------------------------------------
# Storage: an S3 bucket for application assets.
# random_id keeps the globally-unique bucket name unique per deployment.
# ---------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project}-assets-${random_id.suffix.hex}"
  tags   = { Name = "${var.project}-assets" }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

# An inventory file that depends on the compute layer, so Terraform must build
# the network and instances BEFORE this object can exist.
resource "aws_s3_object" "inventory" {
  bucket       = aws_s3_bucket.assets.id
  key          = "inventory.json"
  content_type = "application/json"

  content = jsonencode({
    project    = var.project
    owner      = var.common_tags["Owner"]
    roll       = var.common_tags["Roll"]
    vpc_id     = aws_vpc.main.id
    vpc_cidr   = aws_vpc.main.cidr_block
    subnet_ids = [aws_subnet.public.id, aws_subnet.private.id]
    instances  = [for i in aws_instance.web : { id = i.id, private_ip = i.private_ip }]
  })
}
