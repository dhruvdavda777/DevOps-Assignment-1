# ---------------------------------------------------------------------------
# Networking: VPC -> IGW -> subnets -> route tables -> security groups
# Every dependency below is INFERRED from references, never declared.
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id # <- this reference creates the dependency
  tags   = { Name = "${var.project}-igw" }
}

# cidrsubnet() carves the VPC range up arithmetically rather than by hand:
#   cidrsubnet("10.42.0.0/16", 8, 1) = "10.42.1.0/24"
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = var.az
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-public", Tier = "public" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 11)
  availability_zone = var.az

  tags = { Name = "${var.project}-private", Tier = "private" }
}

# A subnet is "public" ONLY because its route table points 0.0.0.0/0 at an IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-rt-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---- security groups -------------------------------------------------------

resource "aws_security_group" "web" {
  name        = "${var.project}-web"
  description = "Allow HTTP/HTTPS from anywhere and SSH from inside the VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from within the VPC only - never 0.0.0.0/0"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-web" }
}

resource "aws_security_group" "db" {
  name        = "${var.project}-db"
  description = "Postgres, reachable ONLY from the web security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Postgres from the web tier"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # Referencing a security group, not a CIDR: the rule keeps working as
    # instances come and go.
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-db" }
}
