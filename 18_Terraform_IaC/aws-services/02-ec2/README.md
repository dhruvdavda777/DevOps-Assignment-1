# AWS EC2 – Elastic Compute Cloud

**Name:** Dhruv Davda · **Roll No:** 24BCS10203 · **Group:** A

## What is EC2?

EC2 provides **virtual machines on demand**. You choose an operating system image, a hardware size
and a network, and you get a server in minutes, billed per second. It is the oldest and most
general-purpose AWS compute service — anything that runs on Linux or Windows runs on EC2.

Where it sits among the compute options:

| Service | You manage | Good for |
|---|---|---|
| **EC2** | OS, patching, scaling, runtime | Full control, legacy apps, custom kernels |
| ECS / EKS | Containers | Containerised workloads |
| Lambda | Just the function | Event-driven, spiky workloads |
| Fargate | Just the container | Containers without managing nodes |

## AMI — Amazon Machine Image

A read-only template containing the OS and any pre-installed software. It determines what the
instance boots.

- **AWS-provided**: Amazon Linux 2023, Ubuntu, Windows Server.
- **Marketplace**: vendor-built, sometimes with extra licence cost.
- **Custom**: your own "golden image", built with Packer or by snapshotting a configured instance.

AMIs are **region-specific** — the same logical image has a different ID in `ap-south-1` than in
`us-east-1`, which is a common Terraform portability bug. The fix is a data source rather than a
hardcoded ID:

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

Baking dependencies into a custom AMI shortens boot time and removes a runtime dependency on package
repositories — the same argument as building a Docker image rather than installing at startup.

## Instance types

Named `family + generation + size`, e.g. **`t3.micro`**, **`m6i.large`**:

| Family | Optimised for | Example use |
|---|---|---|
| **T** (t3, t4g) | Burstable, cheap | Dev boxes, low-traffic sites |
| **M** (m6i) | Balanced | General servers, app tiers |
| **C** (c7g) | Compute | Batch processing, game servers |
| **R / X** | Memory | Databases, in-memory caches |
| **I / D** | Storage | NoSQL, data warehouses |
| **P / G** | GPU | ML training, rendering |

A `g` suffix (`t4g`, `c7g`) means **AWS Graviton (ARM)** — usually cheaper per unit of performance,
but your container images must be built for `arm64`. That is precisely the architecture mismatch I
hit in Session 16, where a GitHub-hosted amd64 runner produced an image my ARM Mac could not run.

**T-family burst credits** are a classic surprise: a `t3.micro` accumulates CPU credits while idle and
spends them under load. Exhaust them and the instance is throttled hard, which looks like a mysterious
performance cliff.

## Key pairs

An SSH public/private key pair. AWS stores the **public** key and injects it into the instance;
**you keep the private key and AWS cannot recover it.** Lose it and you cannot SSH in — recovery means
detaching the root volume and attaching it to another instance.

Better than key pairs for most cases: **AWS Systems Manager Session Manager**, which gives shell
access through the SSM agent with no SSH port open, no key to lose, and full audit logging in
CloudTrail.

## Security Groups

A **stateful virtual firewall** attached to an instance's network interface.

| | Security Group | Network ACL |
|---|---|---|
| Attached to | Instance / ENI | Subnet |
| Rules | **Allow only** | Allow **and** deny |
| State | **Stateful** — return traffic is automatic | Stateless — need explicit both directions |
| Evaluation | All rules together | Numbered, first match wins |

**Stateful** is the key property: allow inbound 443 and the response is automatically permitted. With
a NACL you must also allow the outbound ephemeral port range.

Security groups can reference **other security groups** as a source, which is how you express "the
web tier may reach the database tier" without hardcoding IPs — the AWS equivalent of the Docker
network isolation in Topic 07 and Kubernetes NetworkPolicies.

## EBS — Elastic Block Store

Network-attached block storage that persists independently of the instance.

| Type | Use |
|---|---|
| `gp3` | General purpose SSD, the sensible default |
| `io2` | Provisioned IOPS, for demanding databases |
| `st1` / `sc1` | Throughput/cold HDD, for logs and archives |

Points that matter:

- EBS volumes live in **one Availability Zone** and can only attach to an instance in that AZ.
- **Snapshots** go to S3 and are the mechanism for backup and for moving a volume between AZs.
- **Delete on termination** defaults to `true` for the root volume — a common accidental data loss.
- **Instance store** is physically attached, much faster, and **lost on stop/terminate**.

The EBS-vs-instance-store distinction is the same lesson as Kubernetes `PersistentVolume` vs
`emptyDir` from Session 13: one outlives the compute, one does not.

## Public vs private IP

| | Private IP | Public IP | Elastic IP |
|---|---|---|---|
| Range | RFC 1918 (`10.0.0.0/8` …) | AWS-assigned public | AWS-assigned public |
| Survives a stop/start | **Yes** | **No, it changes** | **Yes** |
| Cost | Free | Free while attached | Charged when **not** attached |

The trap: a public IP is released when an instance stops, so anything referencing it breaks. Use an
**Elastic IP** for a fixed address, or better, a load balancer or DNS name.

A public IP is **not configured on the instance itself** — the OS only ever sees the private address,
and the internet gateway does 1:1 NAT. `ifconfig` showing only a private address is normal and not a
fault. (The same thing surprised me on Docker Desktop in Topic 05, where the client IP in container
logs was the VM gateway rather than my laptop.)

## Instance lifecycle

```
pending ──> running ──┬──> stopping ──> stopped ──> (start) ──> pending
                      └──> shutting-down ──> terminated   [irreversible]
```

| Action | RAM | Root EBS | Public IP | Billing |
|---|---|---|---|---|
| **Stop** | Lost | Kept | Released | Storage only |
| **Hibernate** | **Written to EBS** | Kept | Released | Storage only |
| **Reboot** | Kept | Kept | Kept | Continues |
| **Terminate** | Lost | **Deleted** (by default) | Released | Stops |

**Terminate is irreversible.** `disable_api_termination` (termination protection) exists for exactly
this reason on anything important.

## Common use cases

- **Web/application servers** behind an ALB in an Auto Scaling Group across multiple AZs.
- **Self-managed databases** where RDS does not fit (custom extensions, unsupported engines).
- **Batch / CI runners** on Spot Instances — up to ~90% cheaper, interruptible with 2 minutes' notice.
- **Bastion hosts** for access to private subnets (increasingly replaced by Session Manager).
- **Lift-and-shift** migrations of existing VMs before re-architecting.

## Terraform sketch

```hcl
resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.admin.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx && systemctl enable --now nginx
  EOF

  tags = { Name = "web-dhruv", Owner = "24BCS10203" }
}
```

`user_data` runs **once, on first boot** — the simplest form of provisioning, and the reason an EC2
instance can be configured without ever logging into it.
