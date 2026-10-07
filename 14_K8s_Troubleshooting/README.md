# Session 14 – Kubernetes Troubleshooting

**Name:** Dhruv Davda · **Roll No:** 24BCS10203 · **Email:** Dhruv.24bcs10203@sst.scaler.com · **Group:** A

Run against my `dhruv-devops` kind cluster. All ten failure modes in
[`manifests/broken.yaml`](./manifests/broken.yaml) were deployed **simultaneously**, diagnosed, fixed
and verified.

---

## Task 1: The troubleshooting command set

| Command | What it answers | When it is the right tool |
|---|---|---|
| `kubectl get` | What exists, and what state is it in | **Always first** |
| `kubectl get -o wide` | Which node, which Pod IP | Scheduling and networking issues |
| `kubectl describe` | Spec + **Events** | **A Pod that is not running** |
| `kubectl logs` | What the app printed | A Pod that *is* running, badly |
| `kubectl logs --previous` | What the **dead** container printed | CrashLoopBackOff |
| `kubectl exec` | A shell inside the container | Verifying config/connectivity from inside |
| `kubectl get events` | Cluster-wide, time-ordered | Something changed and I do not know what |
| `kubectl explain` | API field documentation | "Is this field even real?" |
| `kubectl top` | Actual CPU/memory | OOM kills, throttling, HPA problems |

The single most useful rule:

> **Not running → `describe` (read the Events). Running but wrong → `logs`.**

`kubectl logs` on a Pod that never started returns nothing useful, because there is no container to
have produced output — demonstrated below.

### get: the first look

```console
$ kubectl get pods -l demo=troubleshooting
NAME                READY   STATUS                       RESTARTS      AGE
ts-badrepo          0/1     ImagePullBackOff             0             84s
ts-crashloop        0/1     Error                        3 (68s ago)   84s
ts-imagepull        0/1     ImagePullBackOff             0             84s
ts-missing-config   0/1     CreateContainerConfigError   0             84s
ts-missing-pvc      0/1     Pending                      0             84s
ts-oomkill          0/1     OOMKilled                    0             84s
ts-pending          0/1     Pending                      0             84s
```

### get -o wide: adds the two columns that matter for networking

```console
$ kubectl get pods -l demo=troubleshooting -o wide
NAME                READY   STATUS                       RESTARTS      AGE   IP            NODE
ts-badrepo          0/1     ImagePullBackOff             0             84s   10.244.1.78   dhruv-devops-worker
ts-crashloop        0/1     Error                        3 (68s ago)   84s   10.244.1.76   dhruv-devops-worker
ts-missing-pvc      0/1     Pending                      0             84s   <none>        <none>
ts-pending          0/1     Pending                      0             84s   <none>        <none>
```

**`<none>` in both IP and NODE is diagnostic on its own**: those two Pods were never scheduled, so
nothing about images, containers or networking can possibly be the cause.

### events: the cluster-wide timeline

```console
$ kubectl get events --sort-by=.lastTimestamp | tail -6
37s  Warning  Failed   pod/ts-badrepo     Failed to pull image "dhruv24bcs10203/no-such-image:v1": ... pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
35s  Warning  Failed   pod/ts-imagepull   Failed to pull image "nginx:does-not-exist-9.9.9": ... docker.io/library/nginx:does-not-exist-9.9.9: not found
11s  Warning  Failed   pod/ts-imagepull   Error: ImagePullBackOff
4s   Warning  Failed   pod/ts-missing-config  Error: configmap "config-that-does-not-exist" not found
```

`--sort-by=.lastTimestamp` matters — the default order is not chronological, which makes events far
harder to read than they need to be.

### explain and top

```console
$ kubectl explain pod.spec.containers.livenessProbe.failureThreshold
$ kubectl top pods -l app=cpu-app
NAME                       CPU(cores)   MEMORY(bytes)
cpu-app-7d686fdc64-4rh7q   306m         11Mi
```

(`kubectl top` requires metrics-server — installed in Session 13.)

---

## Task 2: Ten issues, diagnosed and fixed

### 1. CrashLoopBackOff

**Identify**

```console
NAME           READY   STATUS   RESTARTS      AGE
ts-crashloop   0/1     Error    3 (68s ago)   84s
```

**Investigate** — `describe` gives the exit code:

```console
$ kubectl describe pod ts-crashloop | grep -E 'Last State:|Exit Code:|Reason:|Restart Count:'
      Reason:       Error
      Exit Code:    1
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
    Restart Count:  4
```

…but the exit code only says *that* it failed. The **logs** say why:

```console
$ kubectl logs ts-crashloop
reading config...
cat: can't open '/etc/app/config.yaml': No such file or directory
```

**A real difficulty worth recording:** `kubectl logs --previous` repeatedly failed here —

```console
$ kubectl logs ts-crashloop --previous
unable to retrieve container logs for containerd://09ca887a1170a1b578fb6797a69ba6e252ec2bc0d9d9c59a37ee987899c51ae3
```

The container exits after about a second, and once the kubelet has garbage-collected that container
its logs are gone. Plain `kubectl logs`, run during a short-lived `Running` window, is what actually
worked. **With a very fast crash loop, catch the logs between restarts, or add a `sleep` to the
command to widen the window.**

**Root cause:** the app reads `/etc/app/config.yaml`; nothing mounts anything there.

**Fix** — the ConfigMap has to exist **and be mounted**. My first attempt only created it, which
changed nothing:

```yaml
      volumeMounts: [{name: cfg, mountPath: /etc/app}]
  volumes:
    - name: cfg
      configMap: {name: app-config}
```

**Verify**

```console
$ kubectl get pods -l demo=troubleshooting | grep crashloop
ts-crashloop   1/1   Running   0   50s

$ kubectl logs ts-crashloop
reading config...
owner: dhruv-24bcs10203
config OK, staying up
```

---

### 2 & 3. ImagePullBackOff vs ErrImagePull — and why the message matters

Two Pods, both `ImagePullBackOff`, **completely different causes**:

```console
# bad TAG, real repository
$ kubectl describe pod ts-imagepull | grep 'Failed to pull'
Failed to pull image "nginx:does-not-exist-9.9.9": rpc error: code = NotFound desc = ...
  "docker.io/library/nginx:does-not-exist-9.9.9": not found

# bad REPOSITORY
$ kubectl describe pod ts-badrepo | grep 'Failed to pull'
Failed to pull image "dhruv24bcs10203/no-such-image:v1": ... pull access denied,
  repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
```

**`not found` = the tag is wrong. `pull access denied / insufficient_scope` = the repository is wrong
*or* you need credentials.** A registry cannot distinguish "does not exist" from "exists but you may
not see it" without leaking information, so a typo'd repository name looks exactly like an auth
failure. This sends people hunting for `imagePullSecrets` when the real problem is a typo.

`ErrImagePull` is the *first* failure; `ImagePullBackOff` is the state after repeated retries.

**Fix:** correct the tag. Pods are immutable, so the Pod must be recreated (a Deployment would just
need `kubectl set image`).

```console
$ kubectl get pods -l demo=troubleshooting | grep imagepull
ts-imagepull   1/1   Running   0   20s
```

---

### 4. Pending — unschedulable

```console
$ kubectl describe pod ts-pending | sed -n '/Events:/,$p' | tail -1
Warning  FailedScheduling  102s (x6 over 104s)  default-scheduler  0/2 nodes are available:
  1 Insufficient cpu, 1 Insufficient memory, 1 node(s) had untolerated taint(s).
  preemption: 0/2 nodes are available: 2 Preemption is not helpful for scheduling.
```

The scheduler **accounts for every node separately** and says why each was rejected.

```console
$ kubectl get pod ts-pending -o jsonpath='requests={...requests}'
requests={"cpu":"64","memory":"256Gi"}

$ kubectl get nodes -o custom-columns=NODE:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory
NODE                         CPU   MEM
dhruv-devops-control-plane   10    16339940Ki
dhruv-devops-worker          10    16339940Ki
```

**Root cause:** 64 CPUs / 256Gi requested; each node has 10 CPUs and ~15.6Gi.

**Scheduling compares against `requests`, never against actual usage.** An idle node with 10 free
CPUs will still reject a Pod requesting 64.

**Fix + verify:** request `cpu: 100m, memory: 64Mi` → `ts-pending-fixed  1/1  Running`.

---

### 5. CreateContainerConfigError

```console
$ kubectl describe pod ts-missing-config | sed -n '/Events:/,$p' | tail -1
Warning  Failed  12s (x9 over 104s)  kubelet  Error: configmap "config-that-does-not-exist" not found
```

**This is the case that proves the "describe vs logs" rule:**

```console
$ kubectl logs ts-missing-config
Error from server (BadRequest): container "app" in pod "ts-missing-config" is waiting to start: CreateContainerConfigError
```

`logs` returns no application output at all — the container was never created, because the kubelet
could not assemble its configuration. Only `describe` has the answer.

Note the image **was** pulled successfully first. The failure is strictly later, at container-config
assembly.

**Fix + verify:** create the ConfigMap, recreate the Pod → `1/1 Running`.

---

### 6. Pending on a missing PVC

```console
$ kubectl describe pod ts-missing-pvc | sed -n '/Events:/,$p' | tail -1
Warning  FailedScheduling  104s  default-scheduler  0/2 nodes are available:
  persistentvolumeclaim "pvc-that-does-not-exist" not found. not found
```

Same `Pending` status as issue 4, **entirely different cause** — storage, not CPU. The scheduler will
not place a Pod whose volumes cannot be satisfied.

**Fix + verify:**

```console
$ kubectl get pvc pvc-that-does-not-exist
pvc-that-does-not-exist   Bound   pvc-d028dc82-...   64Mi   RWO   standard   73s
ts-missing-pvc            1/1     Running   0   4m23s
```

The Pod scheduled itself once the claim existed — no recreate needed, because the scheduler keeps
retrying.

---

### 7. OOMKilled

```console
$ kubectl get pod ts-oomkill -o jsonpath='reason={...terminated.reason} exit={...exitCode} limit={...limits.memory}'
reason=OOMKilled exit=137 limit=64Mi
```

**Exit code 137 = 128 + 9 (SIGKILL).** The kernel's OOM killer, not the app, ended it — so there is
no graceful shutdown and often nothing useful in the logs.

**Root cause:** the container allocates 300MB against a 64Mi limit.

**Fix + verify:**

```console
$ kubectl logs ts-oomkill
allocated 300MB successfully
$ kubectl get pod ts-oomkill -o jsonpath='phase={.status.phase} reason={...reason}'
phase=Succeeded reason=Completed
```

In production the question is always "is the limit too low, or does the app leak?" — `kubectl top
pods` over time answers it. Raising a limit to hide a leak only delays the failure.

---

### 8. Service connectivity — selector matches nothing

```console
$ kubectl get svc ts-svc
NAME     TYPE        CLUSTER-IP      PORT(S)   AGE
ts-svc   ClusterIP   10.96.142.156   80/TCP    2m7s      <-- looks perfectly healthy

$ kubectl get endpoints ts-svc
ts-svc   <none>   2m7s                                   <-- the actual diagnosis
```

```console
$ kubectl exec tsclient -- curl -sS --max-time 5 http://ts-svc
curl: (7) Failed to connect to ts-svc:80 after 18 ms: Could not connect to server
```

**18 ms — an instant refusal, not a timeout.** DNS resolved fine; there was simply no backend.

The decisive test is to run the Service's own selector as a query:

```console
$ kubectl get svc ts-svc -o jsonpath='selector={.spec.selector}'
selector={"app":"ts-application"}

$ kubectl get pods -l app=ts-app --show-labels --no-headers | head -1
ts-app-54b4665c56-rfmdf   1/1   Running   0   2m7s   app=ts-app,pod-template-hash=54b4665c56

$ kubectl get pods -l app=ts-application
No resources found in default namespace.
```

**Fix + verify:** `kubectl patch svc ts-svc -p '{"spec":{"selector":{"app":"ts-app"}}}'` → endpoints
appear, `curl` returns **200**.

---

### 9. Wrong `targetPort` — the one that looks healthy

This is the nastier sibling of issue 8, because **the endpoints are not empty**:

```console
$ kubectl get endpoints ts-svc-badport
ts-svc-badport   10.244.1.81:8080,10.244.1.82:8080   2m7s
```

Two endpoints listed — by the usual checklist this Service passes. But:

```console
$ kubectl exec tsclient -- curl -sS --max-time 5 http://ts-svc-badport
curl: (7) Failed to connect to ts-svc-badport:80 after 4 ms: Could not connect to server

$ kubectl get svc ts-svc-badport -o jsonpath='port={...port} targetPort={...targetPort}'
port=80 targetPort=8080
$ kubectl get pod -l app=ts-app -o jsonpath='containerPort={...containerPort}'
containerPort=80
```

**The endpoint list contains port 8080, and nothing is listening there.** Kubernetes does not validate
that `targetPort` matches a real listener — it will happily publish endpoints pointing at a closed
port.

**Lesson: "endpoints exist" is necessary but not sufficient. Check the port number in the endpoint
list, not just its presence.**

**Fix + verify:** patch `targetPort` to 80 → endpoints become `10.244.1.81:80,...`, `curl` → **200**.

---

### 10. DNS issues

```console
$ kubectl exec tsclient -- getent hosts ts-svc.wrong-namespace.svc.cluster.local
command terminated with exit code 2        <-- NXDOMAIN

$ kubectl exec tsclient -- getent hosts ts-svc.default.svc.cluster.local
10.96.142.156   ts-svc.default.svc.cluster.local
```

A wrong namespace is indistinguishable from a wrong Service name at the DNS layer — both are just
"no such name". Full CoreDNS troubleshooting, including why to prefer `getent` over bare `dig`, is in
[`../10_K8s_Networking_Services/coredns/README.md`](../10_K8s_Networking_Services/coredns/README.md).

**The distinction that saves the most time:**

| Symptom | Layer | Means |
|---|---|---|
| Name does not resolve | DNS | Wrong name/namespace, or CoreDNS down |
| Resolves, connection **refused fast** | Service | No endpoints, or wrong `targetPort` |
| Resolves, connection **times out** | Network | NetworkPolicy or firewall dropping packets |

---

## Final verification

```console
$ kubectl get pods -l demo=troubleshooting
NAME                READY   STATUS      RESTARTS   AGE
ts-crashloop        1/1     Running     0          83s
ts-imagepull        1/1     Running     0          20s
ts-missing-config   1/1     Running     0          106s
ts-missing-pvc      1/1     Running     0          4m23s
ts-oomkill          0/1     Completed   0          104s
ts-pending-fixed    1/1     Running     0          108s

$ kubectl get endpoints ts-svc ts-svc-badport
NAME             ENDPOINTS                       AGE
ts-svc           10.244.1.81:80,10.244.1.82:80   3m50s
ts-svc-badport   10.244.1.81:80,10.244.1.82:80   3m50s

  curl http://ts-svc           -> HTTP 200
  curl http://ts-svc-badport   -> HTTP 200
```

All ten resolved. (`ts-oomkill` is `Completed` because it is a run-to-completion Pod — success for
that workload.)

---

## Task 3: Mini project — a troubleshooting decision tree

```
Pod is not healthy
│
├─ STATUS = Pending
│   └─ kubectl describe pod → Events
│       ├─ "Insufficient cpu/memory"      → requests too high, or cluster full
│       ├─ "untolerated taint"            → add a toleration / nodeSelector
│       └─ "persistentvolumeclaim not found" → create the PVC
│
├─ STATUS = ImagePullBackOff / ErrImagePull
│   └─ kubectl describe pod → read the pull error
│       ├─ "not found"                    → wrong TAG
│       └─ "pull access denied / insufficient_scope" → wrong REPO, or missing imagePullSecret
│
├─ STATUS = CreateContainerConfigError
│   └─ describe → a ConfigMap/Secret named in envFrom or volumes does not exist
│
├─ STATUS = CrashLoopBackOff / Error
│   └─ kubectl logs --previous  (and plain logs between restarts)
│       ├─ app error / missing file       → fix config or mount
│       └─ exit 137 + Reason OOMKilled    → memory limit too low, or a leak
│
├─ STATUS = Running but READY 0/1
│   └─ describe → "Readiness probe failed"
│       └─ wrong path/port, or the app genuinely is not ready
│
└─ Pod healthy, but clients cannot reach it
    └─ kubectl get endpoints <svc>
        ├─ <none>        → selector does not match Pod labels
        ├─ wrong port    → targetPort ≠ containerPort
        └─ correct       → DNS? NetworkPolicy? Check from a client Pod with curl
```

### The four commands that resolve most incidents

```bash
kubectl get pods -o wide                       # 1. what is broken, and where
kubectl describe pod <pod>                     # 2. why, if it never started
kubectl logs <pod> --previous                  # 3. why, if it started and died
kubectl get endpoints <svc>                    # 4. why clients cannot reach it
```

### Things this session taught me that I would not have guessed

- **`logs` is useless for a Pod that never started** — `CreateContainerConfigError` returns an API
  error instead of output. `describe` is the only route.
- **A fast crash loop can destroy its own evidence.** `--previous` failed repeatedly here because the
  container was garbage-collected between attempts.
- **`Pending` is two unrelated problems** (scheduling vs storage) wearing the same label.
- **Endpoints existing does not mean the Service works** — issue 9 had healthy-looking endpoints
  pointing at a dead port.
- **"Repository does not exist" and "you lack permission" are the same message**, by design, so a
  typo masquerades as an auth problem.
- **Refused-fast vs timed-out is the fastest way to split Service problems from network problems** —
  the same distinction as the `nc` results back in Topic 03.

## Clean up

```console
$ kubectl delete -f manifests/broken.yaml --ignore-not-found
$ kubectl delete pod tsclient ts-pending-fixed ts-imagepull --ignore-not-found
$ kubectl delete cm app-config config-that-does-not-exist --ignore-not-found
$ kubectl delete pvc pvc-that-does-not-exist --ignore-not-found
```
