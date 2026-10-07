output "bucket_name" {
  description = "Name of the created bucket"
  value       = aws_s3_bucket.assignment.id
}

output "bucket_arn" {
  description = "ARN of the created bucket"
  value       = aws_s3_bucket.assignment.arn
}

output "bucket_region" {
  description = "Region the bucket lives in"
  value       = aws_s3_bucket.assignment.region
}

output "versioning_status" {
  description = "Whether object versioning is enabled"
  value       = aws_s3_bucket_versioning.assignment.versioning_configuration[0].status
}

output "object_key" {
  description = "Key of the uploaded object"
  value       = aws_s3_object.readme.key
}

output "public_access_blocked" {
  description = "Confirms all four public-access blocks are on"
  value = alltrue([
    aws_s3_bucket_public_access_block.assignment.block_public_acls,
    aws_s3_bucket_public_access_block.assignment.block_public_policy,
    aws_s3_bucket_public_access_block.assignment.ignore_public_acls,
    aws_s3_bucket_public_access_block.assignment.restrict_public_buckets,
  ])
}
