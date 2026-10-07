# DevOps Assignment

**Name:** Dhruv Davda  
**Roll No:** 24BCS10203  
**Email:** Dhruv.24bcs10203@sst.scaler.com  
**Group:** A

All 21 sessions of the DevOps course. Each folder has a `README.md` containing the commands I ran,
the real output from my terminal, and what I took from it. Where something produced a web page there
are browser screenshots; where it produced Kubernetes or cloud objects there is `kubectl` / `terraform`
/ AWS CLI output.

## Session → folder map

> Folders `01`–`11` were numbered by topic before the session list was published, so **session numbers
> and folder numbers differ below session 13**. Sessions 01 and 02 share one folder, and there is no
> folder `12` — session 12 lives in `11_K8s_Ingress_ConfigMaps_Secrets`.

| Session | Topic | README |
|---|---|---|
| 01 & 02 | Linux Fundamentals | [01_Linux_Fundamental/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/01_Linux_Fundamental/README.md) |
| 03 | Shell Scripting | [02_shell_scripting/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/02_shell_scripting/README.md) |
| 04 | Networking Fundamentals | [03_networking/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/03_networking/README.md) |
| 05 | Git / GitHub | [04_git/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/04_git/README.md) |
| 06 | Docker Fundamentals | [05_Docker_Fundamental/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/05_Docker_Fundamental/README.md) |
| 07 | Dockerfiles & Images | [06_DockerFiles_Images/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/06_DockerFiles_Images/README.md) |
| 08 | Docker Networking & Volumes | [07_Docker_Networking/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/07_Docker_Networking/README.md) |
| 09 | Kubernetes Fundamentals | [08_Kubernetes_Fundamentals/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/08_Kubernetes_Fundamentals/README.md) |
| 10 | K8s Pods, ReplicaSets & Deployments | [09_K8s_Pods_ReplicaSets_Deployments/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/09_K8s_Pods_ReplicaSets_Deployments/README.md) |
| 11 | K8s Networking & Services | [10_K8s_Networking_Services/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/10_K8s_Networking_Services/README.md) |
| 12 | K8s Ingress, ConfigMaps & Secrets | [11_K8s_Ingress_ConfigMaps_Secrets/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/11_K8s_Ingress_ConfigMaps_Secrets/README.md) |
| 13 | K8s Storage, HPA & Probes | [13_K8s_Storage_HPA_Probes/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/13_K8s_Storage_HPA_Probes/README.md) |
| 14 | Kubernetes Troubleshooting | [14_K8s_Troubleshooting/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/14_K8s_Troubleshooting/README.md) |
| 15 | Helm | [15_Helm/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/15_Helm/README.md) |
| 16 | CI/CD & GitHub Actions | [16_CICD_GitHub_Actions/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/16_CICD_GitHub_Actions/README.md) |
| 17 | Complete CI/CD & DevSecOps | [17_CICD_DevSecOps/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/17_CICD_DevSecOps/README.md) |
| 18 | Terraform & Infrastructure as Code | [18_Terraform_IaC/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/18_Terraform_IaC/README.md) |
| 19 | Cloud & Terraform in Action | [19_Cloud_Terraform_Action/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/19_Cloud_Terraform_Action/README.md) |
| 20 | Monitoring, Observability & GitOps | [20_Monitoring_Observability_GitOps/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/20_Monitoring_Observability_GitOps/README.md) |
| 21 | Final DevOps Project | [21_Final_DevOps_Project/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/21_Final_DevOps_Project/README.md) |

## Highlights

| | |
|---|---|
| **Live CI/CD pipeline** | [Session 16 run #37623670800](https://github.com/dhruvdavda777/DevOps-Assignment-1/actions/runs/37623670800) — 5 jobs, all green |
| **Live DevSecOps pipeline** | [Session 17 run #37625008502](https://github.com/dhruvdavda777/DevOps-Assignment-1/actions/runs/37625008502) — SAST, SCA, secret + image scanning, security gate |
| **Extra deep-dives** | [FQDN](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/10_K8s_Networking_Services/fqdn/README.md) · [CoreDNS](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/10_K8s_Networking_Services/coredns/README.md) · [Volumes](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/13_K8s_Storage_HPA_Probes/01-kubernetes-volumes/README.md) |
| **AWS research** | [IAM](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/18_Terraform_IaC/aws-services/01-iam/README.md) · [EC2](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/18_Terraform_IaC/aws-services/02-ec2/README.md) · [S3](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/18_Terraform_IaC/aws-services/03-s3/README.md) · [VPC](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/18_Terraform_IaC/aws-services/04-vpc/README.md) · [DynamoDB & RDS](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/18_Terraform_IaC/aws-services/05-dynamodb-rds/README.md) |

## Environment

- **Host:** macOS on Apple Silicon (`aarch64`)
- **Docker:** engine 29.4.3 · **Helm:** v4.3.0 · **Terraform:** v1.16.1 · **kind:** v0.33.0
- **Kubernetes:** local 2-node kind cluster, v1.37.0 — config in [`08_Kubernetes_Fundamentals/kind-cluster.yaml`](./08_Kubernetes_Fundamentals/kind-cluster.yaml)
- **Security tooling:** Trivy 0.75.0, gitleaks 8.30.1, Semgrep (container)
- **Cloud:** Terraform runs against **LocalStack 3.8**, since my AWS credentials had expired. The
  configuration is identical to a real deployment; only the provider endpoints differ, and every
  divergence is called out in the relevant README.
- **Class repository** used for the session 07 multi-stage build: <https://github.com/Nency-Ravaliya/devops-heros>

## A note on what is written up

A fair number of these labs failed on the first attempt. Those failures are documented rather than
edited out, because the diagnosis is usually the part worth keeping. A few examples:

- **Session 03** — the CPU model printed blank: `model name` in `/proc/cpuinfo` is x86-only and this is an ARM machine.
- **Session 07** — the class multi-stage Dockerfile saved only 6 MB. Measured, not assumed: the project has no `devDependencies`.
- **Session 08** — `--network host` hit `Address in use`, then proved unreachable from macOS because "host" is the Docker Desktop VM.
- **Session 11** — `dig` reported NXDOMAIN for names that applications resolve fine, because `dig` ignores the `search` list.
- **Session 12** — the Ingress controller landed on the wrong node, so `hostPort: 80` bound a port nothing could reach.
- **Session 15** — `helm upgrade` reported **"deployed"** for a release whose Pod was in `ImagePullBackOff`.
- **Session 17** — gitleaks silently ignored AWS's documentation example key; Semgrep missed an MD5 hash with two rulesets.
- **Session 18** — LocalStack hung on S3 lifecycle configuration after creating five resources correctly.
- **Session 21** — a `Recreate` rollout meant my first two fault captures sampled the wrong Pod.

Secret values committed under `11_.../manifests/secret.yaml` and `21_.../kubernetes/01-config.yaml` are
throwaway strings written for this assignment; both READMEs explain why a real Secret manifest does not
belong in Git.
