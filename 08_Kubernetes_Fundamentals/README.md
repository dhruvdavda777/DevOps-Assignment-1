# Topic 08 – Kubernetes Fundamentals

**Name:** Dhruv Davda
**Roll No:** 24BCS10203
**Email:** Dhruv.24bcs10203@sst.scaler.com
**Group:** A

My cluster is a local two-node [kind](https://kind.sigs.k8s.io/) cluster named `dhruv-devops`,
created from [`kind-cluster.yaml`](./kind-cluster.yaml). The same cluster is used for Topics 09, 10
and 11.

```console
$ brew install kind
$ kind create cluster --config kind-cluster.yaml
Creating cluster "dhruv-devops" ...
 ✓ Ensuring node image (kindest/node:v1.37.0) 🖼
 ✓ Preparing nodes 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-dhruv-devops"
```

The config gives the control-plane node the `ingress-ready` label and maps host ports 80/443, which
Topic 11 needs for the ingress controller:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: dhruv-devops
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
```

---

## 1. Kubernetes architecture in short

### Control plane — decides what should happen

| Component | Responsibility |
|---|---|
| **kube-apiserver** | The only way in. Validates every request and is the sole component that talks to etcd. |
| **etcd** | Distributed key-value store holding all cluster state. Lose etcd and you lose the cluster. |
| **kube-scheduler** | Watches for Pods with no node assigned and picks one, based on resources, affinity and taints. |
| **kube-controller-manager** | Runs the reconciliation loops (Deployment, ReplicaSet, Node, Job …) that drive actual state toward desired state. |
| **cloud-controller-manager** | Cloud-specific integration — load balancers, volumes. Absent on kind. |

### Worker node — makes it happen

| Component | Responsibility |
|---|---|
| **kubelet** | The node agent. Takes Pod specs from the API server and asks the runtime to start containers. Reports status back. |
| **container runtime** | Actually runs containers. `containerd://2.3.4` on my nodes. |
| **kube-proxy** | Programmes iptables/IPVS so Service IPs route to the right Pods. |
| **CNI plugin** | Pod networking. kind uses `kindnet`. |

The central idea is the **reconciliation loop**: I declare what I want, controllers continuously
compare that to reality and act on the difference. Nothing is imperative — even `kubectl run` just
writes a desired-state object and lets the loops do the work.

---

## 2. Cluster information

```console
$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:54929
CoreDNS is running at https://127.0.0.1:54929/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

$ kubectl version
Client Version: v1.34.1
Kustomize Version: v5.7.1
Server Version: v1.37.0
Warning: version difference between client (1.34) and server (1.37) exceeds the supported minor version skew of +/-1
```

Worth recording that warning: my Homebrew `kubectl` is **v1.34.1** while the kind node image ships
Kubernetes **v1.37.0**. The supported skew is ±1 minor version and I am 3 ahead, so newer server
fields might not be understood by my client. Everything in these topics worked, but on a real
cluster I would match the client to the server version.

```console
$ kubectl get nodes -o wide
NAME                         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   OS-IMAGE                       KERNEL-VERSION             CONTAINER-RUNTIME
dhruv-devops-control-plane   Ready    control-plane   22m   v1.37.0   172.19.0.3    Debian GNU/Linux 13 (trixie)   6.12.76-linuxkit (arm64)   containerd://2.3.4
dhruv-devops-worker          Ready    <none>          22m   v1.37.0   172.19.0.2    Debian GNU/Linux 13 (trixie)   6.12.76-linuxkit (arm64)   containerd://2.3.4

$ kubectl config current-context
kind-dhruv-devops

$ kubectl config get-contexts
CURRENT   NAME                CLUSTER             AUTHINFO            NAMESPACE
*         kind-dhruv-devops   kind-dhruv-devops   kind-dhruv-devops
```

The nodes' internal IPs `172.19.0.x` are on the `kind` Docker bridge network — **the "nodes" are
Docker containers on my laptop**, which is what makes kind so quick to throw away and recreate.

---

## 3. The architecture components are real Pods

```console
$ kubectl get pods -n kube-system -o wide
NAME                                                 READY   STATUS    RESTARTS   AGE   IP           NODE
coredns-559f6c778d-544bf                             1/1     Running   0          22m   10.244.0.2   dhruv-devops-control-plane
coredns-559f6c778d-d96kk                             1/1     Running   0          22m   10.244.0.4   dhruv-devops-control-plane
etcd-dhruv-devops-control-plane                      1/1     Running   0          22m   172.19.0.3   dhruv-devops-control-plane
kindnet-q2jsj                                        1/1     Running   0          22m   172.19.0.3   dhruv-devops-control-plane
kindnet-qrgrx                                        1/1     Running   0          22m   172.19.0.2   dhruv-devops-worker
kube-apiserver-dhruv-devops-control-plane            1/1     Running   0          22m   172.19.0.3   dhruv-devops-control-plane
kube-controller-manager-dhruv-devops-control-plane   1/1     Running   0          22m   172.19.0.3   dhruv-devops-control-plane
kube-proxy-fbvjs                                     1/1     Running   0          22m   172.19.0.2   dhruv-devops-worker
kube-proxy-zgkgm                                     1/1     Running   0          22m   172.19.0.3   dhruv-devops-control-plane
kube-scheduler-dhruv-devops-control-plane            1/1     Running   0          22m   172.19.0.3   dhruv-devops-control-plane
```

Reading the table against the theory in section 1:

- `etcd`, `kube-apiserver`, `kube-controller-manager`, `kube-scheduler` all run **only on the
  control-plane node**, and all show the node's own IP `172.19.0.3` — they use **host networking**,
  which they must, since the API server has to be reachable before Pod networking exists. These are
  **static Pods**, created by the kubelet from manifests on disk rather than by the API server. That
  resolves the chicken-and-egg problem of "how does the API server get started by the API server".
- `kube-proxy` and `kindnet` appear **once per node** — they are DaemonSets, which is exactly the
  workload type Topic 09 covers.
- `coredns` has **2 replicas with Pod IPs `10.244.0.x`** from the Pod CIDR, not the node CIDR. It is
  an ordinary Deployment with ordinary Pod networking, because DNS is a cluster service rather than
  part of the node bootstrap.

**`RESTARTS 0` across the board** means the control plane came up cleanly first time — which matches
what `journalctl -p err` reported on this node back in Topic 01.

---

## 4. Node capacity and API resources

```console
$ kubectl describe node dhruv-devops-worker | sed -n '/Capacity/,/System Info/p'
Capacity:
  cpu:                15
  ephemeral-storage:  977843695616
  memory:             8125988Ki
  pods:               110
Allocatable:
  cpu:                15
  ephemeral-storage:  977843695616
  memory:             8125988Ki
  pods:               110

$ kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.capacity.memory,PODS:.status.capacity.pods
NAME                         CPU   MEM         PODS
dhruv-devops-control-plane   15    8125988Ki   110
dhruv-devops-worker          15    8125988Ki   110
```

- **`Capacity` is the hardware total; `Allocatable` is what is left for Pods** after reserving for
  the kubelet and system daemons. Here they are identical, because kind sets no system reservations.
- **`pods: 110`** is the default per-node cap — a scheduling limit, not a memory one. A node can hit
  it with plenty of RAM free.
- Both nodes report 15 CPUs and ~7.7 GiB, i.e. **the same figures** — and the same numbers my
  `sysinfo.sh` script reported in Topic 02. That is because both "nodes" are containers sharing one
  Docker Desktop VM. Each node *believes* it has the whole machine, so the scheduler could
  over-commit 30 CPUs' worth of requests onto hardware that has 15. Fine for learning, and a real
  trap if you benchmark on kind.

```console
$ kubectl api-resources | head -12
NAME                       SHORTNAMES   APIVERSION   NAMESPACED   KIND
bindings                                v1           true         Binding
componentstatuses          cs           v1           false        ComponentStatus
configmaps                 cm           v1           true         ConfigMap
endpoints                  ep           v1           true         Endpoints
events                     ev           v1           true         Event
limitranges                limits       v1           true         LimitRange
namespaces                 ns           v1           false        Namespace
nodes                      no           v1           false        Node
persistentvolumeclaims     pvc          v1           true         PersistentVolumeClaim
persistentvolumes          pv           v1           false        PersistentVolume
pods                       po           v1           true         Pod

$ kubectl api-resources | wc -l
      72

$ kubectl api-versions | head -6
admissionregistration.k8s.io/v1
apiextensions.k8s.io/v1
apiregistration.k8s.io/v1
apps/v1
authentication.k8s.io/v1
authorization.k8s.io/v1
```

`kubectl api-resources` is the most useful discovery command in Kubernetes: it gives the short name
(`po`, `deploy`, `svc`), the API group to put in `apiVersion:`, and whether the resource is
namespaced. The `APIVERSION` column is where `apps/v1` for a Deployment versus plain `v1` for a Pod
comes from.

---

## 5. My first Pod

```console
$ kubectl run first-pod --image=nginx:1.27-alpine
pod/first-pod created

$ kubectl wait --for=condition=Ready pod/first-pod --timeout=90s
pod/first-pod condition met

$ kubectl get pod first-pod -o wide
NAME        READY   STATUS    RESTARTS   AGE   IP           NODE
first-pod   1/1     Running   0          7s    10.244.1.2   dhruv-devops-worker
```

The scheduler put it on the **worker**, and it got Pod IP `10.244.1.2` — note `10.244.**1**.x` for
the worker versus `10.244.**0**.x` for the control plane. Each node owns a slice of the Pod CIDR.

The event list is the Pod lifecycle, in order:

```console
$ kubectl describe pod first-pod | sed -n '/Events:/,$p'
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  7s    default-scheduler  Successfully assigned default/first-pod to dhruv-devops-worker
  Normal  Pulling    6s    kubelet            Pulling image "nginx:1.27-alpine"
  Normal  Pulled     0s    kubelet            Successfully pulled image "nginx:1.27-alpine" in 6.116s (6.116s including waiting). Image size: 21832241 bytes.
  Normal  Created    0s    kubelet            Container created
  Normal  Started    0s    kubelet            Container started
```

**`From` names the responsible component**, which makes the division of labour concrete:
`default-scheduler` chose the node, then `kubelet` did everything else. This events list is the
first place to look when a Pod misbehaves — Topic 09 uses it to diagnose a broken image.

```console
$ kubectl logs first-pod | tail -3
2026/09/17 15:29:08 [notice] 1#1: start worker process 46
2026/09/17 15:29:08 [notice] 1#1: start worker process 47
2026/09/17 15:29:08 [notice] 1#1: start worker process 48

$ kubectl exec first-pod -- nginx -v
nginx version: nginx/1.27.5

$ kubectl exec first-pod -- hostname
first-pod
```

The container's hostname is the **Pod** name, not the node's and not a container ID. Reaching it
without any Service:

```console
$ kubectl port-forward pod/first-pod 8095:80 &
$ curl -s -o /dev/null -w "status=%{http_code}\n" http://localhost:8095
status=200
```

`port-forward` tunnels through the API server straight to the Pod. It is a debugging tool, not a way
to expose an application — that is what Services are for, in Topic 10.

---

## 6. Namespaces

```console
$ kubectl get namespaces
NAME                 STATUS   AGE
default              Active   23m
kube-node-lease      Active   23m
kube-public          Active   23m
kube-system          Active   23m
local-path-storage   Active   23m
```

- `default` — where my objects go if I do not say otherwise.
- `kube-system` — the control plane components from section 3.
- `kube-node-lease` — node heartbeat Lease objects, used for failure detection.
- `kube-public` — world-readable cluster info.
- `local-path-storage` — kind's default StorageClass provisioner.

```console
$ kubectl create namespace dhruv-dev
namespace/dhruv-dev created

$ kubectl run ns-pod --image=nginx:1.27-alpine -n dhruv-dev
pod/ns-pod created

$ kubectl get pods                  # default namespace only
NAME        READY   STATUS    RESTARTS   AGE
first-pod   1/1     Running   0          21s

$ kubectl get pods -n dhruv-dev
NAME     READY   STATUS              RESTARTS   AGE
ns-pod   0/1     ContainerCreating   0          0s

$ kubectl get pods --all-namespaces | grep -E 'NAMESPACE|first-pod|ns-pod'
NAMESPACE   NAME        READY   STATUS              RESTARTS   AGE
default     first-pod   1/1     Running             0          21s
dhruv-dev   ns-pod      0/1     ContainerCreating   0          0s
```

**`kubectl get pods` silently showed only the `default` namespace.** `ns-pod` existed the whole time.
This is the single most common source of "my Pod disappeared" confusion — the answer is nearly
always a forgotten `-n`.

Not everything is namespaced:

```console
$ kubectl api-resources --namespaced=false | head -5
NAME                SHORTNAMES   APIVERSION   NAMESPACED   KIND
componentstatuses   cs           v1           false        ComponentStatus
namespaces          ns           v1           false        Namespace
nodes               no           v1           false        Node
persistentvolumes   pv           v1           false        PersistentVolume
```

Nodes and PersistentVolumes are **cluster-scoped** — physical or cluster-wide things cannot belong
to one team's namespace, while the PersistentVolume*Claim* that requests one is namespaced.

---

## 7. Generating YAML and reading documentation from the CLI

`--dry-run=client -o yaml` builds a valid manifest without touching the cluster. This is how to
write YAML without memorising it:

```console
$ kubectl run yaml-demo --image=nginx:1.27-alpine --dry-run=client -o yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: yaml-demo
  name: yaml-demo
spec:
  containers:
  - image: nginx:1.27-alpine
    name: yaml-demo
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}
```

```console
$ kubectl create deployment web --image=nginx --replicas=3 --dry-run=client -o yaml | head -20
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: web
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  strategy: {}
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - image: nginx
        name: nginx
```

The generated Deployment already shows the structure Topic 09 explains: `spec.selector.matchLabels`
must match `spec.template.metadata.labels`, or the Deployment cannot find the Pods it creates.

`kubectl explain` is the built-in API reference, so I do not need the website:

```console
$ kubectl explain pod.spec.restartPolicy
KIND:       Pod
VERSION:    v1

FIELD: restartPolicy <string>
ENUM:
    Always
    Never
    OnFailure

$ kubectl explain pod.spec.containers.resources
FIELD: resources <ResourceRequirements>

DESCRIPTION:
    Compute Resources required by this container. Cannot be updated.
```

The `ENUM` list is the part worth knowing — it gives the legal values without guessing, and
`Cannot be updated` warns which fields force a Pod replacement rather than an in-place edit.

---

## 8. Clean up

```console
$ kubectl delete pod first-pod
pod "first-pod" deleted from default namespace

$ kubectl delete namespace dhruv-dev     # deletes everything inside it
namespace "dhruv-dev" deleted

$ kubectl get pods --all-namespaces | grep -E 'first-pod|ns-pod' || echo "both gone"
both gone
```

Deleting a namespace deletes every object in it — convenient, and irreversible. I never had to
delete `ns-pod` explicitly.

---

## kubectl cheat sheet

### Discovery and context

| Command | Purpose |
|---|---|
| `kubectl cluster-info` | API server and core service endpoints |
| `kubectl get nodes -o wide` | Nodes with IPs, OS and runtime |
| `kubectl api-resources` | Every resource type, short name, group, scope |
| `kubectl explain <res>.<field>` | Built-in field documentation |
| `kubectl config get-contexts` / `use-context <n>` | List / switch clusters |
| `kubectl config set-context --current --namespace=<ns>` | Stop typing `-n` |

### Everyday inspection

| Command | Purpose |
|---|---|
| `kubectl get pods -o wide` | Add node and Pod IP columns |
| `kubectl get pods -A` | Every namespace |
| `kubectl get pods -w` | Watch changes live |
| `kubectl describe pod <p>` | Full detail **plus the Events list** |
| `kubectl logs <p>` / `-f` / `--previous` | Logs / follow / previous crashed container |
| `kubectl get events --sort-by=.lastTimestamp` | Cluster events in time order |
| `kubectl get pod <p> -o yaml` | The object as stored in etcd |
| `kubectl top pod` / `top node` | Live usage (needs metrics-server) |

### Creating and changing

| Command | Purpose |
|---|---|
| `kubectl run <p> --image=<img>` | A single bare Pod, mostly for testing |
| `kubectl create deployment <d> --image=<img> --replicas=N` | Imperative Deployment |
| `kubectl apply -f file.yaml` | **Declarative — the one to use in practice** |
| `kubectl ... --dry-run=client -o yaml` | Generate a manifest, change nothing |
| `kubectl scale deploy/<d> --replicas=N` | Change replica count |
| `kubectl set image deploy/<d> <c>=<img>` | Trigger a rolling update |
| `kubectl rollout status\|history\|undo deploy/<d>` | Watch, list, roll back |
| `kubectl edit <res>/<name>` | Edit the live object in `$EDITOR` |
| `kubectl delete -f file.yaml` / `delete pod <p>` | Delete |

### Debugging

| Command | Purpose |
|---|---|
| `kubectl exec -it <p> -- sh` | Shell inside a container |
| `kubectl port-forward pod/<p> 8080:80` | Tunnel a local port to a Pod |
| `kubectl cp <p>:/path ./local` | Copy files out of a container |
| `kubectl get pod <p> -o jsonpath='{.status.podIP}'` | Pull one field for a script |
| `kubectl debug -it <p> --image=busybox` | Ephemeral debug container |

---

## Evidence

Every command above is a verbatim transcript from my terminal against the `dhruv-devops` cluster.
The browser-visible parts of this assignment are captured as screenshots in Topics 05, 06, 07 and 11;
Kubernetes object state is better evidenced by the `kubectl` output itself, so that is what is
reproduced here.
