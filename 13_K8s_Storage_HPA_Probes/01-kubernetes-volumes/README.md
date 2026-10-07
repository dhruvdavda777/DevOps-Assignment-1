# Kubernetes Volumes

**Name:** Dhruv Davda · **Roll No:** 24BCS10203 · **Group:** A

Session 13, Task 1. Every output below is from my `dhruv-devops` kind cluster. Manifests are in
[`../manifests/`](../manifests).

## Why volumes exist

A container's filesystem is **ephemeral**: it is part of the container, and when the container is
removed so is everything written to it. That is fine for a stateless web server and fatal for a
database. Volumes decouple a directory's lifetime from the container's.

Three distinct lifetimes are available, and choosing the right one is the whole decision:

| Volume type | Lives as long as | Survives container restart | Survives Pod deletion |
|---|---|---|---|
| `emptyDir` | the **Pod** | Yes | **No** |
| `hostPath` | the **node** | Yes | Yes (but tied to one node) |
| PV / PVC | the **PersistentVolume** | Yes | **Yes** |

---

## emptyDir

Created empty when the Pod is assigned to a node, deleted when the Pod is removed. Its real purpose
is **sharing between containers in the same Pod**.

```yaml
  containers:
    - name: writer
      command: ["sh","-c","... >> /shared/log.txt ..."]
      volumeMounts: [{name: scratch, mountPath: /shared}]
    - name: reader
      command: ["sh","-c","... tail -3 /shared/log.txt ..."]
      volumeMounts: [{name: scratch, mountPath: /shared}]
  volumes:
    - name: scratch
      emptyDir: {}
```

```console
$ kubectl get pods | grep vol-emptydir
vol-emptydir    2/2     Running   0    25s

$ kubectl logs vol-emptydir -c reader | tail -5
writer line 4 at 12:05:18
--- reader sees ---
writer line 5 at 12:05:21
writer line 6 at 12:05:24
writer line 7 at 12:05:27

$ kubectl exec vol-emptydir -c writer -- wc -l /shared/log.txt
9 /shared/log.txt
```

**The `reader` container sees lines the `writer` container produced.** Two separate containers, two
separate filesystems, one shared directory — that is the sidecar pattern (log shippers, proxies,
config reloaders) in its simplest form.

`emptyDir: {medium: Memory}` backs it with tmpfs instead of disk — faster, and it counts against the
Pod's memory limit. Good for caches and for secrets you want never written to disk.

**Use it for:** scratch space, caches, and sharing between containers in one Pod. **Never** for data
you need after the Pod is gone.

---

## hostPath

Mounts a path from the **node's own filesystem** into the Pod.

```yaml
spec:
  nodeName: dhruv-devops-worker      # pin it, since hostPath is node-specific
  volumes:
    - name: host-root
      hostPath:
        path: /etc
        type: Directory
```

```console
$ kubectl exec vol-hostpath -- ls /host-etc | head -6
10-network-magic.conf
10-network-security.conf
adduser.conf
alternatives
apt
bash.bashrc

$ kubectl exec vol-hostpath -- cat /host-etc/hostname
dhruv-devops-worker

$ kubectl get pod vol-hostpath -o jsonpath='node={.spec.nodeName}'
node=dhruv-devops-worker
```

The Pod read the **node's** `/etc/hostname` and it matched the node it was scheduled on — proof the
mount is the host filesystem, not the container image's.

Two serious caveats, which is why `hostPath` is rare in application workloads:

1. **It pins the Pod to one node.** The data is on that node's disk; reschedule elsewhere and the
   data is gone. I had to set `nodeName` explicitly for this reason.
2. **It is a security hole.** Mounting `/` or `/var/run/docker.sock` can give effective root on the
   node. Pod Security Standards restrict it for exactly this reason.

**Use it for:** node-level agents that legitimately need host data — log collectors reading
`/var/log`, monitoring agents reading `/proc`, CNI plugins. These are DaemonSets, which is the
pattern from Topic 09.

---

## PersistentVolume and PersistentVolumeClaim

The split that confuses people at first:

- **PersistentVolume (PV)** — a *piece of storage* in the cluster. Cluster-scoped. Think "the disk".
- **PersistentVolumeClaim (PVC)** — a *request* for storage by a workload. Namespaced. Think "the
  request form".

The separation exists so developers do not need to know what the storage actually is. A Pod
references a PVC by name; whether that is an AWS EBS volume, an NFS export or a directory on the node
is the cluster administrator's concern.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-pvc}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources:
    requests:
      storage: 128Mi
```

### Access modes

| Mode | Short | Meaning |
|---|---|---|
| `ReadWriteOnce` | RWO | Mounted read-write by **one node** (several Pods on that node is allowed) |
| `ReadOnlyMany` | ROX | Read-only by many nodes |
| `ReadWriteMany` | RWX | Read-write by many nodes — needs NFS/CephFS; most block storage cannot |
| `ReadWriteOncePod` | RWOP | Exactly one **Pod**, cluster-wide |

`ReadWriteOnce` is the usual default and the usual surprise: it is per **node**, not per Pod.

---

## StorageClass and dynamic provisioning

A **StorageClass** names a provisioner and its parameters. Its presence is what makes PVs appear on
demand rather than being created by hand.

```console
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  19m
```

Four fields worth reading:

- **`PROVISIONER: rancher.io/local-path`** — kind's provisioner, which creates a directory on the
  node. On EKS this would be `ebs.csi.aws.com`.
- **`RECLAIMPOLICY: Delete`** — when the PVC is deleted, **delete the underlying storage too**.
  `Retain` would keep it for manual recovery. Getting this wrong on a production database is how data
  is lost permanently.
- **`VOLUMEBINDINGMODE: WaitForFirstConsumer`** — do not provision until a Pod actually needs it, so
  the volume is created on the node where the Pod is scheduled. Demonstrated below.
- **`ALLOWVOLUMEEXPANSION: false`** — this class cannot grow a PVC after creation.

### Dynamic provisioning, demonstrated

**I wrote a PVC. I never wrote a PersistentVolume.** Kubernetes created it:

```console
$ kubectl get pvc
NAME                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data-pvc             Bound    pvc-5891b689-8b00-4dcf-b3ec-1996ce8cb839   128Mi      RWO            standard       41s
data-sts-storage-0   Bound    pvc-3d04afef-a3f9-4837-ae4b-fd3c50560dbe   64Mi       RWO            standard       41s
data-sts-storage-1   Bound    pvc-1a72c731-f275-4e38-b92d-da1b535ca709   64Mi       RWO            standard       37s

$ kubectl get pv -o custom-columns=PV:.metadata.name,CLAIM:.spec.claimRef.name,SC:.spec.storageClassName,RECLAIM:.spec.persistentVolumeReclaimPolicy,NODE:'...values[0]'
PV                                         CLAIM                SC         RECLAIM   NODE
pvc-1a72c731-f275-4e38-b92d-da1b535ca709   data-sts-storage-1   standard   Delete    dhruv-devops-worker
pvc-3d04afef-a3f9-4837-ae4b-fd3c50560dbe   data-sts-storage-0   standard   Delete    dhruv-devops-worker
pvc-5891b689-8b00-4dcf-b3ec-1996ce8cb839   data-pvc             standard   Delete    dhruv-devops-worker
```

The PV names are generated (`pvc-<uuid>`), each is bound to exactly one claim, and each carries
**node affinity** to `dhruv-devops-worker` — because `local-path` storage physically lives on that
node's disk.

### WaitForFirstConsumer, demonstrated

A PVC that nothing mounts does not get provisioned:

```console
$ kubectl get pvc unused-pvc
NAME         STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
unused-pvc   Pending                                      standard       7s

$ kubectl describe pvc unused-pvc | sed -n '/Events:/,$p'
Events:
  Type    Reason                Age              From                         Message
  ----    ------                ----             ----                         -------
  Normal  WaitForFirstConsumer  4s (x2 over 7s)  persistentvolume-controller  waiting for first consumer to be created before binding
```

**`Pending` here is correct behaviour, not a fault.** With `Immediate` binding the volume would be
created on an arbitrary node, and a Pod scheduled elsewhere could never mount it. Waiting lets the
scheduler pick the node first. This is a common "my PVC is stuck Pending" false alarm.

### Data really does persist

```console
$ kubectl exec vol-pvc -- cat /data/persistent.txt
written by vol-pvc at Wed Oct  7 12:05:13 UTC 2026

$ kubectl delete pod vol-pvc
pod "vol-pvc" deleted from default namespace
$ kubectl apply -f manifests/03-pvc-dynamic.yaml
persistentvolumeclaim/data-pvc unchanged      <-- the claim was never deleted
pod/vol-pvc created

$ kubectl exec vol-pvc -- cat /data/persistent.txt
written by vol-pvc at Wed Oct  7 12:05:13 UTC 2026
written by vol-pvc at Wed Oct  7 12:06:21 UTC 2026
```

**Both lines.** The Pod was destroyed and recreated; the data outlived it. Note `persistentvolumeclaim
unchanged` — the PVC is a separate object with its own lifecycle, which is exactly the point.

---

## volumeClaimTemplates — one PVC per Pod

A Deployment's Pods would all share one PVC (and with RWO, fight over it). A **StatefulSet** uses
`volumeClaimTemplates` to give each Pod its own:

```yaml
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: standard
        resources: {requests: {storage: 64Mi}}
```

```console
$ kubectl get pvc
data-sts-storage-0   Bound   pvc-3d04afef-...   64Mi   RWO   standard
data-sts-storage-1   Bound   pvc-1a72c731-...   64Mi   RWO   standard
```

The PVC name is `<template>-<statefulset>-<ordinal>` — **derived from the Pod's stable name**, which
is what lets the same storage be reattached:

```console
$ kubectl exec sts-storage-0 -- cat /data/identity.txt   # before
sts-storage-0 first wrote at Wed Oct  7 12:05:13 UTC 2026
  PVC data-sts-storage-0 is bound to PV: pvc-3d04afef-a3f9-4837-ae4b-fd3c50560dbe

$ kubectl delete pod sts-storage-0

$ kubectl exec sts-storage-0 -- cat /data/identity.txt   # after
sts-storage-0 first wrote at Wed Oct  7 12:05:13 UTC 2026
sts-storage-0 first wrote at Wed Oct  7 12:07:09 UTC 2026
  PVC data-sts-storage-0 is bound to PV: pvc-3d04afef-a3f9-4837-ae4b-fd3c50560dbe

  SAME PV reattached -> stable storage identity confirmed
```

**Identical PV UUID before and after**, and the old line is still in the file. This is the storage half
of the "stable identity" property from Topic 10 — `db-0` keeps its name *and* its disk.

One sharp edge: **deleting a StatefulSet does not delete its PVCs.** That is deliberate (it protects
your data) but it means storage leaks quietly unless you clean up claims explicitly.

---

## Summary — choosing a volume type

| I need… | Use |
|---|---|
| Scratch space for one Pod | `emptyDir` |
| To share a directory between containers in one Pod | `emptyDir` |
| An in-memory scratch area | `emptyDir` with `medium: Memory` |
| A node agent to read host files | `hostPath` (DaemonSet) |
| Data that survives the Pod | **PVC** with a StorageClass |
| Per-instance storage for a clustered database | **StatefulSet** + `volumeClaimTemplates` |
| Config or secrets as files | `configMap` / `secret` volumes (Topic 11) |

**The two settings most worth getting right:** `reclaimPolicy` (`Delete` vs `Retain` — whether your
data survives a deleted claim) and `accessModes` (RWO is per node, and most block storage simply
cannot do RWX).
