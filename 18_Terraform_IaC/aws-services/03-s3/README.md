# AWS S3 – Simple Storage Service

**Name:** Dhruv Davda · **Roll No:** 24BCS10203 · **Group:** A

Everything here is backed by the working Terraform project in
[`../../terraform-s3-demo/`](../../terraform-s3-demo), which creates a bucket with versioning,
encryption and public-access blocking.

## What is S3?

S3 is **object storage**: you store whole objects addressed by a key, retrieved over HTTP. It is not
a filesystem — there is no partial write, no append, no rename. Updating one byte means uploading the
whole object again.

| | Object (S3) | Block (EBS) | File (EFS) |
|---|---|---|---|
| Unit | Object + metadata | Fixed-size blocks | Files and directories |
| Access | HTTP API | Attached to one instance | NFS mount, many instances |
| Scales to | Effectively unlimited | Volume size limit | Petabytes |
| Good for | Backups, media, static sites, data lakes | Boot volumes, databases | Shared application data |

Durability is **99.999999999% (11 nines)** — objects are replicated across at least three Availability
Zones automatically.

## Buckets

A bucket is the top-level container.

- **Globally unique name** across all of AWS — not just your account. That is why my Terraform uses
  `dhruv-24bcs10203-devops-assignment` rather than something generic.
- Lives in **one region**; data does not leave it unless you replicate it.
- Naming: 3–63 characters, lowercase, no underscores. My `variables.tf` enforces this before AWS
  ever sees it:

```hcl
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket names must be lowercase, 3-63 characters, and start/end alphanumeric."
  }
```

## Objects

An object is the data plus its key, metadata, and version ID.

**The "folder" is an illusion.** `logs/2026/app.log` is a single flat key that happens to contain
slashes; the console renders them as folders. There are no real directories, which is why listing by
prefix is efficient and "renaming a folder" means copying every object.

Objects can be up to 5 TB; anything over 100 MB should use **multipart upload**, which uploads parts
in parallel and can resume.

## Storage classes

| Class | Retrieval | Min duration | For |
|---|---|---|---|
| **Standard** | Instant | — | Active data |
| **Intelligent-Tiering** | Instant | — | Unpredictable access; AWS moves it for you |
| **Standard-IA** | Instant | 30 days | Infrequent but needs instant access |
| **One Zone-IA** | Instant | 30 days | Re-creatable data; **one AZ only** |
| **Glacier Instant** | Instant | 90 days | Archives queried occasionally |
| **Glacier Flexible** | Minutes–hours | 90 days | Backups |
| **Glacier Deep Archive** | **Up to 12 hours** | 180 days | Compliance retention |

The cheap classes charge a **minimum storage duration** and a per-GB retrieval fee. Moving
short-lived data to Glacier can cost *more* than leaving it in Standard — a classic
over-optimisation.

## Versioning

```hcl
resource "aws_s3_bucket_versioning" "assignment" {
  bucket = aws_s3_bucket.assignment.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}
```

```console
$ terraform output versioning_status
"Enabled"
```

With versioning on, an overwrite creates a new version and a delete writes a **delete marker** —
nothing is actually removed, so both are reversible. This is the main defence against accidental
deletion and against ransomware.

Two consequences: **you pay for every version**, and once enabled versioning can only be *suspended*,
never switched off. Pair it with a lifecycle rule to expire old versions.

## Lifecycle policies

```hcl
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
```

Automatic transition to cheaper storage and eventual deletion, so versioning does not grow costs
without bound.

**This resource is disabled by default in my project** — LocalStack community does not implement the
read-back the AWS provider polls for after writing a lifecycle configuration, so `terraform apply`
timed out after 3 minutes. It is gated behind `var.enable_lifecycle_rules` and documented in the
session README; against real AWS it would be set to `true`.

## Encryption

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "assignment" {
  bucket = aws_s3_bucket.assignment.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

| Option | Key managed by | Notes |
|---|---|---|
| **SSE-S3** (`AES256`) | AWS | Default since 2023, free |
| **SSE-KMS** | AWS KMS, your CMK | Auditable in CloudTrail, per-request cost |
| **SSE-C** | You supply the key per request | AWS stores nothing |
| **Client-side** | You, before upload | AWS never sees plaintext |

**Encryption at rest is on by default now**, but setting it explicitly documents the intent and
satisfies compliance checks. For regulated data, SSE-KMS adds per-key access control and an audit
trail of every decrypt.

## Bucket policies and access control

```hcl
resource "aws_s3_bucket_public_access_block" "assignment" {
  bucket                  = aws_s3_bucket.assignment.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

```console
$ terraform output public_access_blocked
true
```

**This is the most important S3 setting in existence.** Publicly readable buckets are the single most
common cause of large cloud data leaks. All four flags are belt and braces: two ignore existing
public grants, two refuse new ones.

Four overlapping access mechanisms, in rough order of preference:

1. **IAM policies** — identity-based, the normal route.
2. **Bucket policies** — resource-based; required for cross-account and the only way to grant to
   anonymous users.
3. **ACLs** — legacy and discouraged; `BucketOwnerEnforced` disables them entirely.
4. **Presigned URLs** — a time-limited signed link, which is how you give a browser temporary
   download access without making anything public.

Remember from the IAM notes: `s3:ListBucket` acts on the bucket ARN while `s3:GetObject` acts on
`arn:...:bucket/*`. Omitting the `/*` form is the most common S3 permission bug.

## Common use cases

- **Static website hosting** behind CloudFront — the final artifact of a frontend build.
- **Backups and archives**, with lifecycle rules tiering to Glacier.
- **Data lake** — raw data queried in place by Athena.
- **Build artifacts and container-adjacent storage**, like the tarball my Session 16 pipeline uploads.
- **Terraform remote state** with S3 + DynamoDB locking (see the session README).
- **Log destination** for CloudTrail, ALB and VPC flow logs.

## Verified end to end

```console
$ aws --endpoint-url=http://localhost:4566 s3 ls
2026-10-07 18:40:04 dhruv-24bcs10203-devops-assignment

$ aws --endpoint-url=http://localhost:4566 s3 ls s3://dhruv-24bcs10203-devops-assignment/
2026-10-07 18:40:04        147 README.txt

$ aws --endpoint-url=http://localhost:4566 s3 cp s3://dhruv-24bcs10203-devops-assignment/README.txt -
DevOps Assignment - Session 18
Owner : Dhruv Davda
Roll  : 24BCS10203
Env   : dev
Bucket: dhruv-24bcs10203-devops-assignment
Created by Terraform.
```
