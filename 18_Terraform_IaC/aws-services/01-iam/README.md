# AWS IAM – Identity and Access Management (Governance)

**Name:** Dhruv Davda · **Roll No:** 24BCS10203 · **Group:** A

## What is IAM?

IAM is the service that answers one question for every single AWS API call: **is this principal
allowed to perform this action on this resource?** It is global (not regional), free, and it sits in
front of everything else in AWS — an EC2 launch, an S3 read, a Terraform apply all go through it.

Two separate concepts that are easy to confuse:

- **Authentication** — who are you? (user credentials, a role's temporary token, federation)
- **Authorization** — what may you do? (policies)

## Users

An **IAM user** is a long-lived identity for a person or an application, with permanent credentials:

| Credential | Used for |
|---|---|
| Console password | Signing in to the web console |
| Access key ID + secret access key | CLI, SDK, Terraform |

The **root user** is the email address the account was created with. It can do anything, including
closing the account, and cannot be restricted by policy. Best practice is to use it once — to create
an admin user and enable MFA — and then never again.

Long-lived access keys are the main source of AWS credential leaks, because they end up in git
history, CI logs and laptop config files. This is not hypothetical: the credentials on this machine
in `~/.aws/credentials` are exactly the kind of artifact that leaks.

## Groups

A **group** is a collection of users that policies attach to. Users inherit every policy on every
group they belong to.

```
Developers group  ──┬── alice
 (ReadOnly + ECR)   └── bob

Admins group      ──── carol
 (AdministratorAccess)
```

Groups cannot be nested, and a group is not a principal — you cannot give a group a role or have
something "run as" a group. It is purely a convenience for managing permissions at scale: when
someone changes team you move their group membership rather than editing a dozen policies.

## Roles

A **role** is an identity with permissions but **no permanent credentials**. Something *assumes* the
role and receives temporary credentials (typically valid 15 minutes to 12 hours) from STS.

A role has two policy documents, and the distinction matters:

- **Trust policy** — *who may assume this role* (the principal)
- **Permissions policy** — *what the role can do once assumed*

Roles are the correct answer to almost every "how do I give X access to Y" question:

| Scenario | Role type |
|---|---|
| EC2 instance needs to read S3 | Instance profile attached to the EC2 instance |
| Lambda needs to write DynamoDB | Lambda execution role |
| EKS pod needs AWS access | IRSA — service account annotated with a role ARN |
| GitHub Actions needs to deploy | OIDC federated role (**no stored keys at all**) |
| User in account A acts in account B | Cross-account role |

That GitHub Actions row is directly relevant to sessions 16 and 17: instead of storing an AWS access
key as a repository secret, you configure GitHub as an OIDC identity provider and let the workflow
assume a role. Nothing long-lived is ever stored.

## Policies

A policy is a JSON document. The core shape:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadOneBucket",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::dhruv-devops-assignment",
        "arn:aws:s3:::dhruv-devops-assignment/*"
      ],
      "Condition": {
        "IpAddress": {"aws:SourceIp": "203.0.113.0/24"}
      }
    }
  ]
}
```

Note the two ARNs: `s3:ListBucket` acts on the **bucket**, `s3:GetObject` acts on the **objects
inside it**. Forgetting the `/*` variant is one of the most common S3 permission mistakes.

### Policy types

| Type | Attached to | Notes |
|---|---|---|
| **Identity-based** | User, group, role | The usual case |
| **Resource-based** | The resource itself (S3 bucket policy, SQS queue policy) | Can grant cross-account access without a role |
| **Permissions boundary** | User or role | A *ceiling* — caps what identity policies can grant |
| **SCP** (Service Control Policy) | An Organizations OU or account | A ceiling for the whole account; even root is bound by it |
| **Session policy** | Passed at AssumeRole time | Further narrows that session |

### How a decision is actually made

1. **Explicit `Deny` anywhere wins.** Always, and it cannot be overridden.
2. Otherwise an **explicit `Allow`** is required.
3. Otherwise the request is **implicitly denied** (the default).

So permissions are deny-by-default and a single `Deny` in an SCP overrides an `Allow` in a user's
policy. This is what makes permissions boundaries and SCPs useful as guardrails.

## Permissions and least privilege

**Least privilege** means granting exactly the actions, on exactly the resources, needed for the
task — and nothing beyond. The practical difficulty is that you rarely know the exact set up front.
A workable process:

1. Start from an AWS managed policy to get moving.
2. Run the workload.
3. Read **IAM Access Analyzer** / CloudTrail to see which actions were actually called.
4. Generate a tightened policy from that observed activity.
5. Replace the broad policy and re-test.

Anti-patterns worth naming, because they are everywhere:

```json
{"Effect": "Allow", "Action": "*", "Resource": "*"}        // the whole account
{"Effect": "Allow", "Action": "s3:*", "Resource": "*"}     // every bucket, not just yours
```

## IAM best practices

1. **Lock the root user away** — MFA on, no access keys, use it only for the few root-only tasks.
2. **MFA everywhere**, especially for anything with write access.
3. **Roles over users** for anything that is not a human; roles over long-lived keys always.
4. **OIDC federation for CI/CD** — no AWS keys in GitHub secrets.
5. **Identity Center (SSO) for humans** — short-lived console and CLI sessions.
6. **Groups for permissions**, never policies attached directly to individual users.
7. **Rotate and audit** — delete unused keys and users; the IAM credential report lists them.
8. **Permissions boundaries / SCPs** as guardrails so a mistake cannot escalate.
9. **CloudTrail on, in every region**, logging to a bucket in a separate account.
10. **Policies in version control** (Terraform), reviewed like code rather than clicked in a console.

## Common use cases

- **EC2 → S3**: instance profile with a role, so no credentials on the instance.
- **CI/CD deploy**: GitHub Actions OIDC role scoped to one repository and one branch.
- **Cross-account**: a shared tooling account assumes a deploy role in dev/staging/prod.
- **Break-glass**: a rarely used, heavily audited high-privilege role behind MFA.
- **Third-party vendor access**: a role whose trust policy names the vendor's account plus an
  `sts:ExternalId` condition to prevent the confused-deputy problem.

## Relevance to this course

The `ExpiredToken` error I hit when checking credentials for session 18 is IAM working as intended:
the credentials in `~/.aws/credentials` were temporary STS session credentials, and they expired.
Permanent keys would not have expired — which is precisely why temporary credentials are the
recommended model. (For sessions 18 and 19 I used LocalStack instead, so no real IAM principal was
involved.)
