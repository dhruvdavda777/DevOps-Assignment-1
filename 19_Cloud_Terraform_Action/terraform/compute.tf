# ---------------------------------------------------------------------------
# Compute: an AMI lookup and EC2 instances in the public subnet.
# ---------------------------------------------------------------------------

# Never hardcode an AMI id - they differ per region.
data "aws_ami" "linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }
}

resource "aws_instance" "web" {
  count = var.instance_count

  ami                    = data.aws_ami.linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOF
    #!/bin/bash
    amazon-linux-extras install -y nginx1
    echo "<h1>Session 19 - web ${count.index + 1}</h1>" > /usr/share/nginx/html/index.html
    echo "<p>Dhruv Davda - 24BCS10203</p>" >> /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOF

  tags = {
    Name = "${var.project}-web-${count.index + 1}"
    Tier = "web"
  }
}
