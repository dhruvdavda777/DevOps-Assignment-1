# AWS Database Services – DynamoDB and RDS

**Name:** Dhruv Davda · **Roll No:** 24BCS10203 · **Group:** A

Two managed database services with fundamentally different data models. Choosing between them is an
access-pattern decision, not a preference.

---

# DynamoDB

## NoSQL

DynamoDB is a **fully managed key-value and document store**. There are no servers, no instances, no
version upgrades and no connection pool — just an HTTP API.

| | NoSQL (DynamoDB) | Relational (RDS) |
|---|---|---|
| Schema | **Per item**, flexible | Fixed, enforced |
| Joins | **None** | Yes |
| Transactions | Limited, single-table oriented | Full ACID across tables |
| Scaling | **Horizontal, automatic** | Vertical, plus read replicas |
| Query flexibility | Only on indexed keys | Any column, ad hoc |
| Latency | Single-digit ms at any scale | Depends on load and tuning |

The trade is explicit: **you give up ad-hoc querying and get predictable latency at unlimited
scale.**

## Tables, items, attributes

- **Table** — a collection of items. No schema beyond the key.
- **Item** — one record, up to **400 KB**. Analogous to a row.
- **Attribute** — a field on an item. **Two items in the same table need not have the same
  attributes**, apart from the key.

## Partition key and sort key

This is the part that decides whether DynamoDB works for you.

**Partition key (hash key)** — hashed to choose a physical partition. Alone, it must be unique.

**Sort key (range key)** — optional. With it, the *combination* must be unique, and items sharing a
partition key are stored sorted by it, enabling range queries:

```
PK = USER#24BCS10203 , SK = ORDER#2026-01-15
PK = USER#24BCS10203 , SK = ORDER#2026-02-03
PK = USER#24BCS10203 , SK = PROFILE
```

One query returns all orders for a user between two dates — the sort key makes `begins_with` and
`between` efficient.

**Key design mistakes are expensive because the key cannot be changed** without migrating the table:

- A **hot partition** — e.g. partition key = today's date — sends all traffic to one partition and
  throttles regardless of provisioned capacity.
- **Low-cardinality keys** (`status = active`) partition badly.
- A good key is high-cardinality and evenly accessed (`userId`, `tenantId#entityId`).

**Query vs Scan:** `Query` uses the key and is efficient; `Scan` reads **every item** and is the
classic DynamoDB cost and latency mistake. If you need to scan, the data model is probably wrong, or
you need a **Global Secondary Index** — an alternative key on the same data.

Capacity modes: **on-demand** (pay per request, no planning) or **provisioned** (cheaper at steady,
predictable load, with auto-scaling).

## DynamoDB use cases

- Session stores and user profiles — key lookups at high volume.
- Shopping carts, leaderboards, IoT telemetry.
- Event sourcing with **DynamoDB Streams** triggering Lambda.
- **Terraform state locking** — the canonical use, paired with an S3 backend (see the session README).

---

# RDS

## Relational database

RDS runs a **managed relational database**: AWS handles provisioning, patching, backups, failover and
replication; you keep SQL, schemas, joins and transactions.

## Supported engines

| Engine | Notes |
|---|---|
| **PostgreSQL** | Rich feature set, strong extension ecosystem |
| **MySQL / MariaDB** | Widely supported |
| **Aurora** (MySQL/Postgres-compatible) | AWS-built storage layer, faster failover, autoscaling storage |
| **Oracle / SQL Server** | Commercial, licence considerations |

**Aurora Serverless v2** scales capacity automatically, which suits spiky or unpredictable workloads.

## DB instances

Sized like EC2 (`db.t3.micro`, `db.r6g.large`) — the memory-optimised **R** family is the usual
choice, since relational performance is dominated by how much of the working set fits in RAM.

Storage is EBS underneath: `gp3` by default, `io1/io2` for provisioned IOPS, with **storage
autoscaling** available so you do not have to over-provision.

## Security

Layered, and all of it matters:

1. **Network** — put RDS in **private subnets** with no internet route (the Session 18 VPC notes).
2. **Security group** — allow 5432/3306 only from the application tier's security group, never a CIDR.
3. **Authentication** — a master password in **Secrets Manager** (with rotation), or better, **IAM
   database authentication** so no password exists at all.
4. **Encryption** — at rest with KMS (**must be enabled at creation**; you cannot encrypt an existing
   instance in place, only a restored snapshot), and in transit with TLS.
5. **Audit** — Enhanced Monitoring and Performance Insights.

The "no password at all" option is the database version of the lesson from Topic 11: a Secret keeps
credentials out of manifests, but not having a long-lived credential is better still.

## Backups

| | Automated backups | Manual snapshots |
|---|---|---|
| Schedule | Daily + transaction logs | On demand |
| Retention | 0–35 days | **Until deleted** |
| Point-in-time restore | **Yes, to any second** | No, snapshot moment only |
| Deleted with the instance | Yes | **No** |

**Setting retention to 0 disables backups** — an easy and catastrophic mistake. A restore always
creates a **new instance**, so it is not an in-place undo and the application's connection string
must be updated.

## Multi-AZ

A **synchronous standby replica in a different Availability Zone**.

- Failover is automatic, typically 60–120 seconds, by **changing the DNS endpoint** — so applications
  must reconnect rather than cache the IP.
- The standby serves **no traffic**. Multi-AZ is availability, **not** scaling.
- Roughly doubles cost.

## Read replicas

**Asynchronous** copies that *do* serve read traffic.

| | Multi-AZ standby | Read replica |
|---|---|---|
| Replication | Synchronous | **Asynchronous** |
| Serves reads | No | **Yes** |
| Purpose | **Availability** | **Scaling reads** |
| Failover | Automatic | Manual promotion |
| Cross-region | No | **Yes** |

Because replicas are asynchronous they have **replication lag** — a read immediately after a write
may return stale data. Applications must send reads that require consistency to the primary. Most
"the data disappeared after saving" bugs in read-replica architectures are this.

## RDS use cases

- Traditional applications needing joins, transactions and reporting.
- Any workload where the query patterns are not known in advance.
- Migrating an existing MySQL/PostgreSQL application with no code changes.
- Cross-region read replicas for disaster recovery or for serving distant users.

---

# Choosing between them

| Question | DynamoDB | RDS |
|---|---|---|
| Are the access patterns known up front? | **Required** | Not required |
| Do you need joins or ad-hoc SQL? | No | **Yes** |
| Do you need unbounded horizontal scale? | **Yes** | Harder |
| Multi-table ACID transactions? | Limited | **Yes** |
| Operational overhead | Lowest | Low, but version upgrades exist |
| Cost model | Per request | Per instance-hour, running or not |

A practical rule: **if you can write down every query the application will ever make, DynamoDB is
viable and will scale further. If you cannot, use RDS.** Many systems use both — RDS as the system of
record, DynamoDB for sessions and high-volume event data.

This is the same stateless/stateful split that appeared in Topic 06 (Compose: web/api stateless, db
stateful) and Topic 10 (Deployment vs StatefulSet). The storage layer is always the part that
constrains the architecture.
