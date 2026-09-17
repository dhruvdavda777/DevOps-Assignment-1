# Topic 09 – Kubernetes Pods, ReplicaSets, Deployments

**Name:** Dhruv Davda
**Roll No:** 24BCS10203
**Email:** Dhruv.24bcs10203@sst.scaler.com
**Group:** A

Run against the `dhruv-devops` kind cluster from Topic 08. All manifests are in
[`manifests/`](./manifests).

The ownership chain this topic is about:

```
Deployment  ──manages──▶  ReplicaSet  ──manages──▶  Pods  ──contains──▶  Containers
(rollouts,                (replica count,           (scheduling unit,
 rollbacks)                self-healing)              shared network/storage)
```

---

## 1. Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: solo-pod
  labels:
    app: solo
    owner: dhruv
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports:
        - containerPort: 80
      # Requests are what the scheduler uses to place the Pod; limits are the
      # hard ceiling the kernel enforces.
      resources:
        requests:
          cpu: 25m
          memory: 32Mi
        limits:
          cpu: 200m
          memory: 128Mi
      readinessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 2
        periodSeconds: 5
```

```console
$ kubectl apply -f manifests/01-pod.yaml
pod/solo-pod created

$ kubectl get pod solo-pod -o wide --show-labels
NAME       READY   STATUS    RESTARTS   AGE   IP           NODE                  LABELS
solo-pod   1/1     Running   0          6s    10.244.1.4   dhruv-devops-worker   app=solo,owner=dhruv
```

### A bare Pod is not self-healing

```console
$ kubectl delete pod solo-pod
pod "solo-pod" deleted from default namespace

$ kubectl get pods -l app=solo
No resources found in default namespace.
```

**Gone, permanently.** Nothing was watching it. This is why production workloads are never bare
Pods — everything below exists to fix this.

Notes on the spec:
- `requests` vs `limits`: the **scheduler only reads requests** when choosing a node; the **kubelet
  and kernel enforce limits** at runtime. Exceeding a memory limit gets the container OOM-killed;
  exceeding a CPU limit just throttles it.
- A `readinessProbe` controls whether the Pod receives traffic. It is what makes the rolling update
  in section 3 safe — Kubernetes waits for *ready*, not merely *running*.

---

## 2. ReplicaSet – self-healing and scaling

```yaml
spec:
  replicas: 3
  # The selector is how the ReplicaSet finds the Pods it owns. It MUST match
  # the labels in the template, or the controller creates Pods forever.
  selector:
    matchLabels:
      app: web-rs
  template:
    metadata:
      labels:
        app: web-rs
        owner: dhruv
```

```console
$ kubectl apply -f manifests/02-replicaset.yaml
replicaset.apps/web-rs created

$ kubectl get rs web-rs
NAME     DESIRED   CURRENT   READY   AGE
web-rs   3         3         3       6s

$ kubectl get pods -l app=web-rs -o wide
NAME           READY   STATUS    RESTARTS   AGE   IP           NODE
web-rs-84v6f   1/1     Running   0          7s    10.244.1.6   dhruv-devops-worker
web-rs-rsnc2   1/1     Running   0          7s    10.244.1.7   dhruv-devops-worker
web-rs-vdqsh   1/1     Running   0          7s    10.244.1.5   dhruv-devops-worker
```

The Pod names are `web-rs-<random>` — the ReplicaSet generates them, so they are not predictable.

### Self-healing

```console
$ kubectl delete pod web-rs-84v6f
pod "web-rs-84v6f" deleted from default namespace

$ kubectl get pods -l app=web-rs
NAME           READY   STATUS              RESTARTS   AGE
web-rs-fjw7t   0/1     ContainerCreating   0          0s     <-- replacement, already starting
web-rs-rsnc2   1/1     Running             0          17s
web-rs-vdqsh   1/1     Running             0          17s

$ kubectl get pods -l app=web-rs
NAME           READY   STATUS    RESTARTS   AGE
web-rs-fjw7t   1/1     Running   0          5s
web-rs-rsnc2   1/1     Running   0          22s
web-rs-vdqsh   1/1     Running   0          22s
```

The replacement was **already in `ContainerCreating` in the same instant** the delete returned. The
controller's watch fired immediately. And the controller says so itself:

```console
$ kubectl describe rs web-rs | sed -n '/Events:/,$p'
Events:
  Type    Reason            Age   From                   Message
  ----    ------            ----  ----                   -------
  Normal  SuccessfulCreate  23s   replicaset-controller  Created pod: web-rs-84v6f
  Normal  SuccessfulCreate  23s   replicaset-controller  Created pod: web-rs-rsnc2
  Normal  SuccessfulCreate  23s   replicaset-controller  Created pod: web-rs-vdqsh
  Normal  SuccessfulCreate  6s    replicaset-controller  Created pod: web-rs-fjw7t
```

Note it created a **new Pod with a new name**, rather than restarting the old one. Pods are cattle,
not pets: they are replaced, never repaired.

### Scaling

```console
$ kubectl scale rs web-rs --replicas=5
replicaset.apps/web-rs scaled
$ kubectl get rs web-rs
NAME     DESIRED   CURRENT   READY   AGE
web-rs   5         5         5       29s

$ kubectl scale rs web-rs --replicas=2
replicaset.apps/web-rs scaled
$ kubectl get rs web-rs
NAME     DESIRED   CURRENT   READY   AGE
web-rs   2         2         2       34s
```

The **label selector is the entire mechanism**. The ReplicaSet does not track "its" Pods by ID; it
counts Pods matching `app=web-rs` and creates or deletes to reach the target. A consequence worth
knowing: if I manually created a Pod with the label `app=web-rs`, this ReplicaSet would **adopt it**
and delete one of its own to keep the count at 2.

---

## 3. Deployment – rolling update, history, rollback

```yaml
spec:
  replicas: 4
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      # Never drop below 3 available (4 - 1) and never exceed 5 total (4 + 1),
      # so the app stays up throughout the update.
      maxUnavailable: 1
      maxSurge: 1
```

```console
$ kubectl apply -f manifests/03-deployment.yaml
deployment.apps/web-deploy created
Waiting for deployment "web-deploy" rollout to finish: 0 of 4 updated replicas are available...
...
deployment "web-deploy" successfully rolled out

$ kubectl get deploy,rs -l app=web-deploy
NAME                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/web-deploy   4/4     4            4           17s

NAME                                    DESIRED   CURRENT   READY   AGE
replicaset.apps/web-deploy-6b695d4887   4         4         4       17s

$ kubectl get pods -l app=web-deploy
NAME                          READY   STATUS    RESTARTS   AGE
web-deploy-6b695d4887-gwznn   1/1     Running   0          17s
web-deploy-6b695d4887-q6tfh   1/1     Running   0          17s
web-deploy-6b695d4887-rptfd   1/1     Running   0          17s
web-deploy-6b695d4887-xswfg   1/1     Running   0          17s
```

Note the **three-part Pod names**: `web-deploy` (Deployment) + `6b695d4887` (ReplicaSet hash) +
random suffix. The middle segment is a hash of the Pod template, which is exactly how the Deployment
knows whether a ReplicaSet matches the current spec.

### Rolling update

```console
$ kubectl set image deploy/web-deploy web=nginx:1.27-alpine
deployment.apps/web-deploy image updated

$ kubectl rollout status deploy/web-deploy
Waiting for deployment "web-deploy" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "web-deploy" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "web-deploy" rollout to finish: 1 old replicas are pending termination...
deployment "web-deploy" successfully rolled out

$ kubectl get rs -l app=web-deploy \
    -o custom-columns=RS:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,IMAGE:'.spec.template.spec.containers[0].image'
RS                      DESIRED   READY    IMAGE
web-deploy-69f974c9c    4         4        nginx:1.27-alpine
web-deploy-6b695d4887   0         <none>   nginx:1.25-alpine
```

**Two ReplicaSets now exist: the new one at 4, the old one scaled to 0 but kept.** That retained
empty ReplicaSet is the rollback mechanism — nothing is thrown away.

The Deployment controller's events show the update happening step by step:

```console
$ kubectl describe deploy web-deploy | sed -n '/Events:/,$p'
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  19s   deployment-controller  Scaled up replica set web-deploy-6b695d4887 from 0 to 4
  Normal  ScalingReplicaSet  2s    deployment-controller  Scaled up replica set web-deploy-69f974c9c from 0 to 1
  Normal  ScalingReplicaSet  2s    deployment-controller  Scaled down replica set web-deploy-6b695d4887 from 4 to 3
  Normal  ScalingReplicaSet  2s    deployment-controller  Scaled up replica set web-deploy-69f974c9c from 1 to 2
  Normal  ScalingReplicaSet  1s    deployment-controller  Scaled down replica set web-deploy-6b695d4887 from 3 to 2
  Normal  ScalingReplicaSet  1s    deployment-controller  Scaled up replica set web-deploy-69f974c9c from 2 to 3
  Normal  ScalingReplicaSet  1s    deployment-controller  Scaled down replica set web-deploy-6b695d4887 from 2 to 1
  Normal  ScalingReplicaSet  1s    deployment-controller  Scaled up replica set web-deploy-69f974c9c from 3 to 4
  Normal  ScalingReplicaSet  0s    deployment-controller  Scaled down replica set web-deploy-6b695d4887 from 1 to 0
```

This interleaving is the whole point: **up 1, down 1, up 1, down 1**. A Deployment is not a special
primitive — it is a controller that moves two ReplicaSet replica counts in opposite directions,
respecting `maxSurge` and `maxUnavailable` at each step.

### History

```console
$ kubectl rollout history deploy/web-deploy
deployment.apps/web-deploy
REVISION  CHANGE-CAUSE
1         <none>
2         <none>

$ kubectl rollout history deploy/web-deploy --revision=2
deployment.apps/web-deploy with revision #2
Pod Template:
  Labels:	app=web-deploy
	owner=dhruv
	pod-template-hash=69f974c9c
  Containers:
   web:
    Image:	nginx:1.27-alpine
    Port:	80/TCP
    Requests:
      cpu:	10m
      memory:	16Mi
    Readiness:	http-get http://:80/ delay=1s timeout=1s period=3s #success=1 #failure=3
```

### Rollback

```console
$ kubectl rollout undo deploy/web-deploy
deployment.apps/web-deploy rolled back
deployment "web-deploy" successfully rolled out

$ kubectl get deploy web-deploy -o jsonpath='{.spec.template.spec.containers[0].image}'
nginx:1.25-alpine

$ kubectl rollout history deploy/web-deploy
REVISION  CHANGE-CAUSE
2         <none>
3         <none>

$ kubectl get rs -l app=web-deploy -o custom-columns=RS:.metadata.name,DESIRED:.spec.replicas,IMAGE:'.spec.template.spec.containers[0].image'
RS                      DESIRED   IMAGE
web-deploy-69f974c9c    0         nginx:1.27-alpine
web-deploy-6b695d4887   4         nginx:1.25-alpine
```

Two details I would not have guessed:

- **Revision numbers only move forward.** Rolling back to revision 1 created **revision 3**; revision
  1 disappeared from the list. History is an append-only log of what the spec was, not a stack.
- **The ReplicaSets swapped roles rather than being recreated.** `6b695d4887` went 0 → 4 and
  `69f974c9c` went 4 → 0. Same objects, opposite counts — a rollback is just another rolling update
  toward an older template.

### CHANGE-CAUSE is not automatic

`CHANGE-CAUSE` was empty above, which makes the history much less useful. It is simply an annotation:

```console
$ kubectl set image deploy/web-deploy web=nginx:1.27-alpine
$ kubectl annotate deploy/web-deploy kubernetes.io/change-cause="upgrade nginx to 1.27-alpine" --overwrite
deployment.apps/web-deploy annotated

$ kubectl rollout history deploy/web-deploy
REVISION  CHANGE-CAUSE
3         <none>
4         upgrade nginx to 1.27-alpine
```

Setting `kubernetes.io/change-cause` on every deploy (in CI, from the commit message) is what turns
`rollout history` into an actual audit trail.

---

## 4. Troubleshooting – a broken image

Pointing the Deployment at a tag that does not exist:

```console
$ kubectl set image deploy/web-deploy web=nginx:this-tag-does-not-exist
deployment.apps/web-deploy image updated

$ kubectl get pods -l app=web-deploy
NAME                          READY   STATUS             RESTARTS   AGE
web-deploy-5754f4cc74-62f86   0/1     ImagePullBackOff   0          20s
web-deploy-5754f4cc74-vrlvk   0/1     ImagePullBackOff   0          20s
web-deploy-69f974c9c-bsjfd    1/1     Running            0          35s
web-deploy-69f974c9c-mpj26    1/1     Running            0          33s
web-deploy-69f974c9c-wrqz7    1/1     Running            0          33s
```

### Diagnosis

```console
$ kubectl describe pod web-deploy-5754f4cc74-62f86 | sed -n '/Events:/,$p'
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----              -------
  Normal   Scheduled  20s               default-scheduler  Successfully assigned default/web-deploy-5754f4cc74-62f86 to dhruv-devops-worker
  Normal   BackOff    17s               kubelet            Back-off pulling image "nginx:this-tag-does-not-exist"
  Warning  Failed     17s               kubelet            Error: ImagePullBackOff
  Normal   Pulling    7s (x2 over 20s)  kubelet            Pulling image "nginx:this-tag-does-not-exist"
  Warning  Failed     6s (x2 over 18s)  kubelet            Failed to pull image "nginx:this-tag-does-not-exist": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/library/nginx:this-tag-does-not-exist": failed to resolve reference: not found
  Warning  Failed     6s (x2 over 18s)  kubelet            Error: ErrImagePull
```

`kubectl logs` would be useless here — the container never started, so there are no logs. **For a Pod
that is not running, `describe` is the tool; for a Pod that is running badly, `logs` is.**

The `(x2 over 20s)` counter shows the kubelet retrying with exponential backoff, which is the
difference between the two statuses: `ErrImagePull` is a single failed attempt, `ImagePullBackOff` is
"I have failed repeatedly and am now waiting longer between tries".

### The important part: the application never went down

```console
$ kubectl get deploy web-deploy
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
web-deploy   3/4     2            3           79s
```

**3 of 4 still available.** `maxUnavailable: 1` meant the controller would only ever take one old Pod
down before the new one was ready, and since the new Pods never became ready it **stopped and
refused to continue**. A bad image is a stalled rollout, not an outage. With
`maxUnavailable: 4` — or with bare Pods — the same mistake would have taken the whole app offline.

The stall is also detectable in CI, because `rollout status` exits non-zero:

```console
$ kubectl rollout status deploy/web-deploy --timeout=20s
Waiting for deployment "web-deploy" rollout to finish: 2 out of 4 new replicas have been updated...
error: timed out waiting for the condition
```

That non-zero exit is what a pipeline should key off to trigger an automatic rollback.

### Recovery

```console
$ kubectl rollout undo deploy/web-deploy
deployment.apps/web-deploy rolled back
deployment "web-deploy" successfully rolled out

$ kubectl get pods -l app=web-deploy
NAME                         READY   STATUS    RESTARTS   AGE
web-deploy-69f974c9c-bsjfd   1/1     Running   0          74s
web-deploy-69f974c9c-mpj26   1/1     Running   0          72s
web-deploy-69f974c9c-nlv89   1/1     Running   0          4s
web-deploy-69f974c9c-wrqz7   1/1     Running   0          72s

$ kubectl get deploy web-deploy -o jsonpath='{.spec.template.spec.containers[0].image}'
nginx:1.27-alpine
```

Three of the four Pods have the **original 72-second age** — they were never touched. Only the one
Pod that had been removed during the failed rollout had to be recreated.

---

## 5. DaemonSet

A DaemonSet has **no `replicas` field**. It runs one Pod per node.

```yaml
spec:
  template:
    spec:
      # Without this toleration the control-plane node is off limits, because
      # kubeadm taints it. A real node agent needs to run there too.
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: logger
          image: busybox:1.36
          command:
            - sh
            - -c
            - 'while true; do echo "$(date) agent alive on node $NODE_NAME"; sleep 30; done'
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
```

```console
$ kubectl apply -f manifests/04-daemonset.yaml
daemonset.apps/node-logger created

$ kubectl get ds node-logger
NAME          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
node-logger   2         2         2       2            2           <none>          13s

$ kubectl get pods -l app=node-logger -o wide
NAME                READY   STATUS    RESTARTS   AGE   IP            NODE
node-logger-jzw2f   1/1     Running   0          13s   10.244.0.5    dhruv-devops-control-plane
node-logger-stl2p   1/1     Running   0          13s   10.244.1.30   dhruv-devops-worker

$ kubectl get nodes --no-headers | wc -l
       2
```

**`DESIRED 2` because I have 2 nodes** — I never specified a number. Add a third node and a third Pod
appears automatically; drain a node and its Pod goes away.

Each Pod knows which node it is on, via the `fieldRef` downward API:

```console
$ kubectl logs -l app=node-logger --tail=2 --prefix
[pod/node-logger-stl2p/logger] Thu Sep 17 15:34:52 UTC 2026 agent alive on node dhruv-devops-worker
[pod/node-logger-jzw2f/logger] Thu Sep 17 15:34:52 UTC 2026 agent alive on node dhruv-devops-control-plane
```

And scaling is meaningless, which the API enforces:

```console
$ kubectl scale ds node-logger --replicas=5
Error from server (NotFound): the server could not find the requested resource
```

The `tolerations` block was necessary, not decoration. `kubeadm` taints control-plane nodes
`NoSchedule` so ordinary workloads stay off them. This is exactly why `kube-proxy` and `kindnet`
appeared on *both* nodes in Topic 08 — they are DaemonSets with the same toleration. A monitoring
agent that only covered worker nodes would have a blind spot over the most important machine.

---

## Which workload type to use

| Type | Guarantee | Use for |
|---|---|---|
| **Pod** | None. Dies permanently | One-off debugging only |
| **ReplicaSet** | N identical Pods always running | Rarely used directly |
| **Deployment** | ReplicaSets + rollouts + rollback | **Stateless apps — the default** |
| **DaemonSet** | One Pod per node | Log collectors, CNI, monitoring agents |
| **StatefulSet** | Stable names, ordered startup, per-Pod storage | Databases (used in Topic 10) |
| **Job / CronJob** | Run to completion / on a schedule | Batch work, backups, migrations |

---

## Pod status cheat sheet

| Status | Meaning | First thing to check |
|---|---|---|
| `Pending` | Accepted but not scheduled or still pulling | `describe pod` — usually insufficient resources, a taint, or an unbound PVC |
| `ContainerCreating` | Node assigned, image pulling or volumes mounting | Normal briefly; if stuck, check image size and volumes |
| `Running` | All containers started | Check `READY n/n` — running is not the same as ready |
| `Ready 0/1` while Running | Readiness probe failing | `logs`, and check the probe path/port |
| `Succeeded` | All containers exited 0 | Expected for Jobs |
| `Completed` | Same, in `get pods` output | Fine for Jobs, wrong for a Deployment |
| `Failed` | Container exited non-zero | `logs --previous` |
| `CrashLoopBackOff` | Starts, crashes, restarts, repeatedly | **`logs --previous`** — the app is broken or misconfigured |
| `ImagePullBackOff` / `ErrImagePull` | Cannot fetch the image | Typo in tag, private registry, missing `imagePullSecret` |
| `ErrImageNeverPull` | `imagePullPolicy: Never` and not present locally | Load the image onto the node |
| `OOMKilled` | Exceeded its memory limit | Raise the limit or fix the leak |
| `Evicted` | Node under resource pressure | Node disk/memory; set proper requests |
| `Terminating` (stuck) | Deletion blocked | A finalizer, or a process ignoring SIGTERM |
| `CreateContainerConfigError` | A referenced ConfigMap/Secret does not exist | The name in `envFrom`/`valueFrom` (seen in Topic 11) |

The two commands that resolve most of these:

```bash
kubectl describe pod <pod>        # not running -> read the Events list
kubectl logs <pod> --previous     # running badly / crash looping -> read the dead container's logs
```

---

## Clean up

```console
$ kubectl delete -f manifests/
$ kubectl delete rs web-rs
```
