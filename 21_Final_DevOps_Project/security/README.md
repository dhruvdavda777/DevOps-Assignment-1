# Security controls

**Dhruv Davda · 24BCS10203**

| Control | Tool | Where |
|---|---|---|
| SAST | Semgrep | CI, `sast` job |
| SCA | Trivy (fs) | CI, `sca` job |
| Secret scanning | gitleaks | CI, full history (`fetch-depth: 0`) |
| Image scanning | Trivy (image) | CI, before push |
| Security gate | `exit-code: 1` on CRITICAL | CI, blocks the push |
| Runtime: non-root | `runAsNonRoot`, `runAsUser: 1000` | `kubernetes/02-deployment.yaml` |
| Runtime: no privilege escalation | `allowPrivilegeEscalation: false` | same |
| Runtime: drop capabilities | `capabilities: {drop: ["ALL"]}` | same |
| Secrets out of the image | `envFrom.secretRef` | same |
| No public storage | `aws_s3_bucket_public_access_block` | `terraform/main.tf` |

## On the committed Secret

`kubernetes/01-config.yaml` contains a **Secret with a demo value**, clearly marked. A real
deployment must not do this, because a Kubernetes Secret is base64-**encoded**, not encrypted —
anyone with `get secrets` can read it, and committing it puts it in git history forever (deleting
the file does not remove it; only rotating the credential does).

The production options, in rough order of preference:

1. **External Secrets Operator / Secrets Store CSI** — the cluster pulls from AWS Secrets Manager or
   Vault; nothing sensitive is in Git at all.
2. **Sealed Secrets** — encrypted with a cluster public key; the encrypted form is safe to commit.
3. **SOPS** — encrypt the values in-place with age or KMS.
4. **`kubectl create secret`** out of band — works, but is not GitOps and is not reproducible.

The application is written so the secret is never disclosed even by its own API:

```js
// Prove the Secret arrived WITHOUT disclosing it.
api_key_configured: API_KEY.length > 0,
api_key_length: API_KEY.length,
```
