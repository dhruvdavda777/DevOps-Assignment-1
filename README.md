# DevOps Assignment 1

**Name:** Dhruv Davda
**Roll No:** 24BCS10203
**Email:** Dhruv.24bcs10203@sst.scaler.com
**Group:** A

Coursework for the DevOps course. Each topic has its own folder containing a `README.md` with the
commands I ran, the real output from my terminal, and what I took away from it. Where a task
produced something visible in a browser, there are screenshots; where it produced Kubernetes
objects, there is `kubectl` output.

## Submission links

| # | Topic | README |
|---|---|---|
| 1 | Linux Fundamentals | [01_Linux_Fundamental/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/01_Linux_Fundamental/README.md) |
| 2 | Shell Scripting | [02_shell_scripting/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/02_shell_scripting/README.md) |
| 3 | Networking | [03_networking/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/03_networking/README.md) |
| 4 | Git and GitHub | [04_git/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/04_git/README.md) |
| 5 | Docker Fundamentals | [05_Docker_Fundamental/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/05_Docker_Fundamental/README.md) |
| 6 | Dockerfiles and Images | [06_DockerFiles_Images/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/06_DockerFiles_Images/README.md) |
| 7 | Docker Networking and Volumes | [07_Docker_Networking/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/07_Docker_Networking/README.md) |
| 8 | Kubernetes Fundamentals | [08_Kubernetes_Fundamentals/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/08_Kubernetes_Fundamentals/README.md) |
| 9 | Kubernetes Pods, ReplicaSets and Deployments | [09_K8s_Pods_ReplicaSets_Deployments/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/09_K8s_Pods_ReplicaSets_Deployments/README.md) |
| 10 | Kubernetes Networking and Services | [10_K8s_Networking_Services/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/10_K8s_Networking_Services/README.md) |
| 11 | Kubernetes Ingress, ConfigMaps and Secrets | [11_K8s_Ingress_ConfigMaps_Secrets/README.md](https://github.com/dhruvdavda777/DevOps-Assignment-1/blob/main/11_K8s_Ingress_ConfigMaps_Secrets/README.md) |

## Environment

- **Host:** macOS on Apple Silicon (`aarch64`), 15 CPUs / 7.7 GiB visible to containers
- **Docker:** Docker Desktop, engine 29.4.3
- **Linux tasks:** `ubuntu:24.04` container; `journalctl` on a systemd-based kind node
- **Kubernetes:** local 2-node cluster via [kind](https://kind.sigs.k8s.io/) v0.33.0, Kubernetes
  v1.37.0 — config in [`08_Kubernetes_Fundamentals/kind-cluster.yaml`](./08_Kubernetes_Fundamentals/kind-cluster.yaml)
- **Class repository** used for the Topic 06 multi-stage build:
  <https://github.com/Nency-Ravaliya/devops-heros>

## What is in each folder

| Folder | Artefacts besides the README |
|---|---|
| `02_shell_scripting/` | `sysinfo.sh` and the `system_info/` directory it generates |
| `04_git/` | `demo-files/` — files produced by the commit and cherry-pick exercises |
| `05_Docker_Fundamental/` | 6 app directories with Dockerfiles, `screenshots/` |
| `06_DockerFiles_Images/` | `three-tier-app/` (compose stack), `single-stage-comparison/`, `screenshots/` |
| `07_Docker_Networking/` | `bind-mount/`, `screenshots/` |
| `08_Kubernetes_Fundamentals/` | `kind-cluster.yaml` |
| `09_…/`, `10_…/`, `11_…/` | `manifests/` with all Kubernetes YAML, plus `screenshots/` for Topic 11 |

## Notes

Several tasks did not work first time, and in each case the failure turned out to be the most
useful part of the exercise. Those are written up honestly rather than edited out:

- **Topic 02** — the CPU model printed blank, because `model name` in `/proc/cpuinfo` is
  x86-only and my Mac is ARM. The script now falls back through three fields.
- **Topic 05** — the React app returned HTTP 200 with no heading in the HTML. It renders
  client-side, so `curl` tests the server while only a browser tests the app.
- **Topic 06** — the class multi-stage Dockerfile saved just 6 MB over a single-stage build, because
  the project has no `devDependencies` and both stages share the same base image. Measured rather
  than assumed.
- **Topic 07** — `--network host` failed with `Address in use` (the kind cluster already held
  port 80), and once moved to a free port it was reachable from inside the Docker Desktop VM but not
  from macOS at all.
- **Topic 10** — `curl` to an ExternalName Service failed with TLS error 60, because DNS aliasing
  cannot rename a certificate or an HTTP `Host` header.
- **Topic 11** — the Ingress controller was scheduled onto the worker node while the host port
  mappings were on the control-plane node, so `hostPort: 80` bound a port nothing could reach.
  Fixed with a `nodeSelector` and a toleration.

Secret values committed under `11_K8s_Ingress_ConfigMaps_Secrets/manifests/secret.yaml` are
throwaway strings written for this assignment; the README there explains why a real Secret manifest
does not belong in git.
