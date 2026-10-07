output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "public_subnet" {
  value = { id = aws_subnet.public.id, cidr = aws_subnet.public.cidr_block }
}

output "private_subnet" {
  value = { id = aws_subnet.private.id, cidr = aws_subnet.private.cidr_block }
}

output "security_groups" {
  value = { web = aws_security_group.web.id, db = aws_security_group.db.id }
}

output "instance_ids" {
  value = aws_instance.web[*].id
}

output "instance_private_ips" {
  value = aws_instance.web[*].private_ip
}

output "assets_bucket" {
  value = aws_s3_bucket.assets.id
}

output "resource_summary" {
  description = "One-line summary of everything built"
  value = format(
    "VPC %s (%s) | subnets: 2 | SGs: 2 | EC2: %d | bucket: %s",
    aws_vpc.main.id, aws_vpc.main.cidr_block, length(aws_instance.web), aws_s3_bucket.assets.id
  )
}
