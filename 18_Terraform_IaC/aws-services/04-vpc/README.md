# AWS VPC – Virtual Private Cloud (Networking)

**Name:** Dhruv Davda · **Roll No:** 24BCS10203 · **Group:** A

## What is a VPC?

A VPC is a **logically isolated virtual network** inside AWS that you control completely: address
range, subnets, routing, and firewalls. Nothing enters or leaves unless you build a path for it.

Every account has a **default VPC** per region with public subnets and an internet gateway already
attached — convenient, and the reason people accidentally launch databases on the public internet.
Production workloads should use a purpose-built VPC.

## CIDR

A VPC is defined by a CIDR block, e.g. `10.0.0.0/16`.

| CIDR | Mask | Addresses |
|---|---|---|
| /16 | 255.255.0.0 | 65,536 |
| /20 | 255.255.240.0 | 4,096 |
| /24 | 255.255.255.0 | 256 |
| /28 | 255.255.255.240 | 16 (AWS minimum) |

This is the same prefix arithmetic as Topic 03, where my campus network turned out to be a `/21`
(`255.255.248.0`, 2046 usable hosts).

**AWS reserves 5 addresses in every subnet**, not the usual 2: network address, VPC router, DNS,
a future-use address, and broadcast. So a `/28` gives **11** usable addresses, not 14.

The CIDR **cannot be shrunk after creation** (you can add secondary ranges). Choose a block that will
not overlap anything you might later peer with — overlapping CIDRs make VPC peering impossible.

## Subnets

A subnet is a slice of the VPC CIDR that lives in **exactly one Availability Zone**. Spreading
subnets across AZs is how you survive an AZ failure.

```
VPC 10.0.0.0/16
├── 10.0.1.0/24  public   ap-south-1a   -> route to IGW
├── 10.0.2.0/24  public   ap-south-1b   -> route to IGW
├── 10.0.11.0/24 private  ap-south-1a   -> route to NAT
└── 10.0.12.0/24 private  ap-south-1b   -> route to NAT
```

## Public vs private subnet

**The only thing that makes a subnet "public" is its route table.** There is no flag.

| | Public subnet | Private subnet |
|---|---|---|
| Default route `0.0.0.0/0` points to | **Internet Gateway** | **NAT Gateway** (or nothing) |
| Reachable from the internet | Yes, with a public IP | **No** |
| Can reach the internet | Yes | Yes, outbound only, via NAT |
| Typically holds | Load balancers, bastions, NAT gateway | App servers, databases |

## Route tables

A route table maps destination CIDRs to targets, and the **most specific prefix wins** — exactly the
behaviour I saw in `netstat -rn` in Topic 03.

| Destination | Target | Meaning |
|---|---|---|
| `10.0.0.0/16` | `local` | Within the VPC. **Always present, cannot be removed** |
| `0.0.0.0/0` | `igw-…` | Everything else to the internet (public subnet) |
| `0.0.0.0/0` | `nat-…` | Everything else via NAT (private subnet) |

## Internet Gateway

A horizontally-scaled, highly available component attached to the VPC that allows **bidirectional**
internet traffic. It also performs 1:1 NAT between an instance's private address and its public
address — which is why an EC2 instance's OS only ever sees the private IP.

Two things are required for internet access: a route to the IGW **and** a public IP on the instance.
Either one missing and it does not work.

## NAT Gateway

Lets instances in **private** subnets make outbound connections (package updates, API calls) while
remaining unreachable from outside.

- Lives in a **public** subnet, needs an Elastic IP.
- **One per AZ** for high availability — a single NAT is both a failure point and a cross-AZ data
  charge.
- **Not free**: hourly charge plus per-GB processing. Often the largest surprise line on a bill.
  **VPC endpoints** avoid it for AWS services (S3, DynamoDB) by keeping traffic on the AWS network.

| | Internet Gateway | NAT Gateway |
|---|---|---|
| Direction | In and out | **Outbound only** |
| Attached to | The VPC | A specific subnet |
| Cost | Free | Hourly + per GB |
| Needed for | Public subnets | Private subnet egress |

## Security Groups vs Network ACLs

| | Security Group | Network ACL |
|---|---|---|
| Level | Instance / ENI | **Subnet** |
| Rules | **Allow only** | Allow **and deny** |
| State | **Stateful** | **Stateless** |
| Evaluation | All rules, any match allows | Numbered, **first match wins** |
| Default | Deny all in, allow all out | Default NACL allows everything |

**Stateless is the one that catches people.** With a NACL, allowing inbound 443 is not enough — the
response leaves from an ephemeral port, so you must also allow outbound `1024-65535`. A security
group tracks the connection and handles this automatically.

Practical guidance: use **security groups as the primary control** (they are expressive and can
reference other groups), and NACLs only as a coarse subnet-wide backstop, typically to block a
specific CIDR.

Referencing one security group from another is the cleanest pattern:

```hcl
resource "aws_security_group_rule" "db_from_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.app.id   # not a CIDR
}
```

"The app tier may reach the database tier on 5432" — and it keeps working as instances come and go.
Conceptually identical to the Docker network isolation in Topic 07 and to Kubernetes
NetworkPolicies.

## A reference architecture

```
                    Internet
                        │
                  ┌─────▼─────┐
                  │    IGW    │
                  └─────┬─────┘
        ┌───────────────┴───────────────┐
   ┌────▼─────────────┐          ┌──────▼───────────┐
   │ Public  AZ-a     │          │ Public  AZ-b     │
   │ 10.0.1.0/24      │          │ 10.0.2.0/24      │
   │  ALB, NAT GW     │          │  ALB, NAT GW     │
   └────┬─────────────┘          └──────┬───────────┘
   ┌────▼─────────────┐          ┌──────▼───────────┐
   │ Private AZ-a     │          │ Private AZ-b     │
   │ 10.0.11.0/24     │          │ 10.0.12.0/24     │
   │  app servers     │          │  app servers     │
   └────┬─────────────┘          └──────┬───────────┘
   ┌────▼─────────────┐          ┌──────▼───────────┐
   │ Data AZ-a        │          │ Data AZ-b        │
   │ 10.0.21.0/24     │          │ 10.0.22.0/24     │
   │  RDS primary     │          │  RDS standby     │
   └──────────────────┘          └──────────────────┘
```

Only the load balancer is exposed. Application servers reach the internet outbound through NAT; the
database has no internet route at all. This is the same "publish only the edge" principle as the
three-tier Docker Compose stack in Topic 06, where Postgres had no published port.

## Common use cases

- **Multi-tier applications** with public/private/data subnet separation.
- **Hybrid connectivity** to on-premises via Site-to-Site VPN or Direct Connect.
- **VPC peering / Transit Gateway** to connect environments — requires non-overlapping CIDRs.
- **VPC endpoints** to reach S3 and DynamoDB privately and avoid NAT charges.
- **VPC Flow Logs** for traffic auditing and for debugging "why is this connection timing out".

The last one connects to Topic 03: a **timeout** means packets are being dropped silently (a NACL,
security group or missing route), while **connection refused** means the host was reached and nothing
was listening. That distinction is the fastest way to tell a VPC problem from an application problem.
