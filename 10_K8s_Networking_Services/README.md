# Topic 10 – Kubernetes Networking and Services

**Name:** Dhruv Davda
**Roll No:** 24BCS10203
**Email:** Dhruv.24bcs10203@sst.scaler.com
**Group:** A

Run against the `dhruv-devops` kind cluster. Manifests in [`manifests/`](./manifests).

## Why Services exist

Topic 09 established that **Pods are disposable and their IPs are not stable**. When I deleted the
ReplicaSet's Pods, replacements came back with new names and new IPs. So no client can hold a Pod IP.

A Service provides:

1. **A stable virtual IP and DNS name** that outlives any individual Pod.
2. **Load balancing** across all healthy Pods matching its selector.
3. **Automatic membership**, driven by labels rather than configuration.

The app used throughout is an nginx Deployment configured to return its own Pod name, so
load balancing is visible in the response:

```nginx
return 200 "served by pod $hostname\n";
```

Tests are run from a `client` Pod running `nicolaka/netshoot` (curl, dig, nslookup), because
ClusterIP Services are only reachable from inside the cluster.

---

## 1. ClusterIP

```yaml
apiVersion: v1
kind: Service
metadata:
  name: whoami-clusterip
spec:
  type: ClusterIP
  selector:
    app: whoami        # matches Pod labels, NOT the Deployment name
  ports:
    - name: http
      port: 80         # the port the Service listens on
      targetPort: 80   # the port on the Pod
```

```console
$ kubectl apply -f manifests/01-clusterip/
configmap/whoami-conf created
deployment.apps/whoami created
pod/client created
service/whoami-clusterip created

$ kubectl get svc whoami-clusterip
NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
whoami-clusterip   ClusterIP   10.96.152.162   <none>        80/TCP    16s

$ kubectl get endpoints whoami-clusterip
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME               ENDPOINTS                                      AGE
whoami-clusterip   10.244.1.31:80,10.244.1.32:80,10.244.1.34:80   16s

$ kubectl get pods -l app=whoami -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP            NODE
whoami-ff5dbf989-98p4x   1/1     Running   0          16s   10.244.1.31   dhruv-devops-worker
whoami-ff5dbf989-d5sdf   1/1     Running   0          16s   10.244.1.34   dhruv-devops-worker
whoami-ff5dbf989-tlv2z   1/1     Running   0          16s   10.244.1.32   dhruv-devops-worker
```

**The three endpoint IPs are exactly the three Pod IPs.** The endpoint list is not configuration — it
is computed continuously by the endpoints controller from the label selector.

Also worth noting: `v1 Endpoints is deprecated in v1.33+`. The modern API is EndpointSlice, which
scales better because a Service with thousands of Pods is split into multiple slice objects rather
than one enormous object:

```console
$ kubectl get endpointslices -l kubernetes.io/service-name=whoami-clusterip
NAME                     ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
whoami-clusterip-mpt6z   IPv4          80      10.244.1.34,10.244.1.31,10.244.1.32   28s
```

### DNS

```console
$ kubectl exec client -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

$ kubectl exec client -- nslookup whoami-clusterip
Address:	10.96.0.10#53

Name:	whoami-clusterip.default.svc.cluster.local
Address: 10.96.152.162
```

The short name `whoami-clusterip` worked because of the **`search` list** in `/etc/resolv.conf`. The
FQDN pattern is:

```
<service>.<namespace>.svc.cluster.local
```

Which means a Pod in another namespace must use `whoami-clusterip.default` at minimum. `10.96.0.10`
is the CoreDNS Service — itself a ClusterIP Service, listed in `kubectl cluster-info` back in
Topic 08.

### Load balancing

```console
$ for i in $(seq 1 9); do kubectl exec client -- curl -s http://whoami-clusterip; done | sort | uniq -c
   1 served by pod whoami-ff5dbf989-98p4x
   4 served by pod whoami-ff5dbf989-d5sdf
   4 served by pod whoami-ff5dbf989-tlv2z
```

All three Pods answered, but the split was **1/4/4, not 3/3/3**. kube-proxy in iptables mode picks a
backend at *random* per connection rather than strict round-robin, so the distribution is only even
on average. For real round-robin or least-connections you need IPVS mode or a service mesh — useful
to know before promising even distribution.

### Proof that the Service follows the Pods

```console
$ kubectl get svc whoami-clusterip -o jsonpath='{.spec.clusterIP}'
10.96.152.162
$ kubectl get endpoints whoami-clusterip -o jsonpath='{.subsets[0].addresses[*].ip}'
10.244.1.31 10.244.1.32 10.244.1.34

$ kubectl delete pods -l app=whoami      # destroy ALL the backends
pod "whoami-ff5dbf989-98p4x" deleted from default namespace
pod "whoami-ff5dbf989-d5sdf" deleted from default namespace
pod "whoami-ff5dbf989-tlv2z" deleted from default namespace
deployment "whoami" successfully rolled out

$ kubectl get pods -l app=whoami -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP            NODE
whoami-ff5dbf989-bwd27   1/1     Running   0          1s    10.244.1.35   dhruv-devops-worker
whoami-ff5dbf989-c7wxc   1/1     Running   0          1s    10.244.1.36   dhruv-devops-worker
whoami-ff5dbf989-s7jk8   1/1     Running   0          1s    10.244.1.37   dhruv-devops-worker

$ kubectl get svc whoami-clusterip -o jsonpath='{.spec.clusterIP}'      # UNCHANGED
10.96.152.162
$ kubectl get endpoints whoami-clusterip -o jsonpath='{.subsets[0].addresses[*].ip}'   # ALL NEW
10.244.1.35 10.244.1.36 10.244.1.37

$ kubectl exec client -- curl -s http://whoami-clusterip
served by pod whoami-ff5dbf989-bwd27
```

**Every backend was destroyed and replaced. The ClusterIP `10.96.152.162` never changed, and the
Service kept working.** The endpoint list silently switched from `.31/.32/.34` to `.35/.36/.37`.

This is the entire value proposition in one experiment: clients hold the Service name, and Pod churn
becomes invisible to them.

Note also that the ClusterIP `10.96.x.x` is from a completely different range than the Pod IPs
`10.244.x.x`. **The ClusterIP is virtual — no network interface anywhere has that address.** It only
exists as iptables/IPVS rules that kube-proxy programmes on every node, which is why it is
unreachable from my Mac but works from any Pod.

---

## 2. NodePort

```yaml
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080   # must be in 30000-32767; omit to let k8s choose
```

```console
$ kubectl get svc whoami-nodeport
NAME              TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
whoami-nodeport   NodePort   10.96.108.124   <none>        80:30080/TCP   3s
```

The `80:30080/TCP` notation means Service port 80, node port 30080. And the node port is open on
**every** node, not only the one running a Pod:

```console
$ docker exec dhruv-devops-control-plane curl -s http://172.19.0.3:30080    # control-plane node
served by pod whoami-ff5dbf989-s7jk8
$ docker exec dhruv-devops-control-plane curl -s http://172.19.0.2:30080    # worker node
served by pod whoami-ff5dbf989-c7wxc
```

- A NodePort Service **is a superset of ClusterIP** — it still got `10.96.108.124`. Adding a NodePort
  does not remove internal access.
- Any node accepts the traffic and forwards it to a Pod, **even a node with no Pod of that app**.
  kube-proxy on that node routes it onward. This is what makes a NodePort work behind a simple
  external load balancer that does not know where Pods live.
- The 30000–32767 restriction and the requirement to remember port numbers per service are why
  NodePort does not scale to many services. It is fine for development and as plumbing under a
  LoadBalancer, but not a public-facing pattern — that is what Ingress in Topic 11 solves.

---

## 3. LoadBalancer

```console
$ kubectl get svc whoami-lb
NAME        TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
whoami-lb   LoadBalancer   10.96.79.21   <pending>     80:32121/TCP   8s
```

**`EXTERNAL-IP` is `<pending>`, and on kind it will stay that way forever.** A LoadBalancer Service
is a *request to the cloud provider* — the cloud-controller-manager is supposed to see it and
provision a real load balancer (an AWS NLB, a GCP forwarding rule). Topic 08 noted that kind has no
cloud-controller-manager, so nothing answers the request. `<pending>` is the correct, honest output,
not a failure of my manifest. (The fix on a local cluster would be a tool like MetalLB or
`cloud-provider-kind`.)

The layering is clearly visible in the describe output:

```console
$ kubectl describe svc whoami-lb | grep -E 'Type|IP:|Port|NodePort|Endpoints'
Type:                     LoadBalancer
IP:                       10.96.79.21
Port:                     http  80/TCP
TargetPort:               80/TCP
NodePort:                 http  32121/TCP
Endpoints:                10.244.1.36:80,10.244.1.37:80,10.244.1.35:80
```

**A LoadBalancer got a ClusterIP *and* a NodePort automatically.** The three types are cumulative:

```
ClusterIP  ⊂  NodePort  ⊂  LoadBalancer
```

And because the NodePort exists, the Service is still perfectly usable despite `<pending>`:

```console
$ docker exec dhruv-devops-control-plane curl -s http://172.19.0.3:32121
served by pod whoami-ff5dbf989-bwd27
```

A real cloud load balancer would simply forward to that node port on every node.

---

## 4. ExternalName

```yaml
spec:
  type: ExternalName
  externalName: api.github.com
```

```console
$ kubectl get svc external-api
NAME           TYPE           CLUSTER-IP   EXTERNAL-IP      PORT(S)   AGE
external-api   ExternalName   <none>        api.github.com   <none>    3s

$ kubectl get endpoints external-api
Error from server (NotFound): endpoints "external-api" not found
```

**No ClusterIP, no ports, and the Endpoints object does not even exist.** ExternalName is not a proxy
at all — it is a CNAME record:

```console
$ kubectl exec client -- nslookup external-api
Server:		10.96.0.10
Address:	10.96.0.10#53

external-api.default.svc.cluster.local	canonical name = api.github.com.
Name:	api.github.com
Address: 20.207.73.85
```

CoreDNS returns a `canonical name` pointing outside the cluster. No traffic passes through
kube-proxy; the Pod connects directly to GitHub.

### It broke, and the failure is the most useful thing in this topic

```console
$ kubectl exec client -- curl -s https://external-api/zen
command terminated with exit code 60
```

```console
$ kubectl exec client -- curl -sS https://external-api/zen
curl: (60) SSL: no alternative certificate subject name matches target hostname 'external-api'
```

**Exit 60 is a TLS certificate verification failure.** DNS was redirected but TLS was not: curl
connected to GitHub and asked for a certificate valid for `external-api`, which of course GitHub does
not have. Confirming the diagnosis by disabling verification:

```console
$ kubectl exec client -- curl -sk https://external-api/zen
<html>
  ...
      <h1>Whoa there!</h1>
      <p>You have sent an invalid request. <br><br>
```

Now TLS succeeds and **GitHub itself rejects the request** — because the `Host` header still said
`external-api`, which is not a site GitHub serves. Two separate layers both assume the real hostname.

The correct fix is to keep verification and send the real hostname for SNI and `Host`:

```console
$ kubectl exec client -- curl -s --connect-to api.github.com:443:external-api:443 https://api.github.com/zen
Responsive is better than fast.
```

That works, with full certificate validation. And plain HTTP never had the problem:

```console
$ kubectl exec client -- curl -s -o /dev/null -w 'status=%{http_code}\n' http://external-api
status=301
```

**The lesson: ExternalName only aliases DNS. It cannot rename a TLS certificate or an HTTP `Host`
header.** So it is genuinely useful for plain-TCP backends (a managed database at
`db.xyz.rds.amazonaws.com` behind the name `db`) and awkward for HTTPS endpoints, where an egress
gateway or just using the real hostname in config is the better answer.

---

## 5. Headless Service + StatefulSet

```yaml
spec:
  clusterIP: None      # this one line makes it headless
  selector:
    app: db
```

```yaml
kind: StatefulSet
spec:
  serviceName: db-headless     # ties the StatefulSet to the headless Service
  replicas: 3
```

### Ordered, named creation

```console
$ kubectl apply -f manifests/05-headless/
statefulset.apps/db created
service/db-headless created

$ kubectl get pods -l app=db -w
db-0   0/1   ContainerCreating   0   3s
db-0   1/1   Running   0   6s | db-1   1/1   Running   0   2s | db-2   1/1   Running   0   1s

$ kubectl get pods -l app=db -o wide
NAME   READY   STATUS    RESTARTS   AGE   IP            NODE
db-0   1/1     Running   0          22s   10.244.1.38   dhruv-devops-worker
db-1   1/1     Running   0          18s   10.244.1.39   dhruv-devops-worker
db-2   1/1     Running   0          17s   10.244.1.40   dhruv-devops-worker
```

Two differences from a Deployment are immediately visible:

- **Names are `db-0`, `db-1`, `db-2`** — ordinal and predictable, not `whoami-ff5dbf989-bwd27`.
- **Creation was sequential.** The watch caught `db-0` alone in `ContainerCreating`, and the ages
  confirm it: 22s, 18s, 17s. `db-1` did not start until `db-0` was Ready. For a database cluster that
  matters enormously — the first Pod can initialise as primary before any replica tries to join.

```console
$ kubectl get svc db-headless
NAME          TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
db-headless   ClusterIP   None         <none>        80/TCP    22s
```

### Headless DNS returns every Pod

```console
$ kubectl exec client -- nslookup db-headless
Name:	db-headless.default.svc.cluster.local
Address: 10.244.1.39
Name:	db-headless.default.svc.cluster.local
Address: 10.244.1.38
Name:	db-headless.default.svc.cluster.local
Address: 10.244.1.40
```

Side by side with the ClusterIP Service, the distinction is stark:

```console
$ kubectl exec client -- dig +short whoami-clusterip.default.svc.cluster.local
10.96.152.162                      <-- one virtual IP

$ kubectl exec client -- dig +short db-headless.default.svc.cluster.local
10.244.1.38
10.244.1.40                        <-- three real Pod IPs
10.244.1.39
```

And each Pod gets its own addressable DNS name:

```console
$ kubectl exec client -- nslookup db-0.db-headless.default.svc.cluster.local
Name:	db-0.db-headless.default.svc.cluster.local
Address: 10.244.1.38
$ kubectl exec client -- nslookup db-1.db-headless.default.svc.cluster.local
Name:	db-1.db-headless.default.svc.cluster.local
Address: 10.244.1.39
$ kubectl exec client -- nslookup db-2.db-headless.default.svc.cluster.local
Name:	db-2.db-headless.default.svc.cluster.local
Address: 10.244.1.40
```

The pattern is `<pod>.<service>.<namespace>.svc.cluster.local`, and it is exactly what a replicated
database needs: a config file can say "replicate from `db-0.db-headless`" and mean one specific Pod.
A ClusterIP Service could never express that — it would load-balance the request to an arbitrary
member, which for a write to a primary would be a correctness bug.

### Stable identity across a restart

```console
$ kubectl delete pod db-1
pod "db-1" deleted from default namespace
pod/db-1 condition met

$ kubectl get pods -l app=db -o custom-columns=NAME:.metadata.name,IP:.status.podIP,AGE:.metadata.creationTimestamp
NAME   IP            AGE
db-0   10.244.1.38   2026-09-17T15:39:05Z
db-1   10.244.1.41   2026-09-17T15:39:45Z
db-2   10.244.1.40   2026-09-17T15:39:10Z
```

**`db-1` came back as `db-1`.** New IP (`.39` → `.41`) and a 40-second-later timestamp, but the same
name and therefore the same DNS record — and, in a real StatefulSet, the same PersistentVolumeClaim.
A Deployment would have produced a Pod with a brand new random name and no way to reattach it to its
old storage.

This is the Kubernetes answer to the stateless/stateful split I ran into with docker compose in
Topic 06: `web` and `api` are Deployments, `db` is a StatefulSet.

---

## 6. Troubleshooting – empty endpoints

The most common Service bug: a selector that matches nothing.

```yaml
spec:
  selector:
    app: whoami-typo      # the real label is app=whoami
```

```console
$ kubectl get svc broken-svc       # looks completely healthy!
NAME         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
broken-svc   ClusterIP   10.96.41.113   <none>        80/TCP    4s
```

**This is the trap.** `kubectl get svc` shows a ClusterIP and a port, and nothing suggests a problem.
The Service object is perfectly valid; it just points at nothing.

```console
$ kubectl get endpoints broken-svc
NAME         ENDPOINTS   AGE
broken-svc   <none>      4s

$ kubectl describe svc broken-svc | grep -E 'Selector|Endpoints'
Selector:                 app=whoami-typo
Endpoints:
```

`ENDPOINTS <none>` is the actual diagnosis. **`kubectl get endpoints` should be the second command
after `kubectl get svc`, always.**

The symptom a client sees:

```console
$ kubectl exec client -- curl -sS --max-time 5 http://broken-svc
curl: (7) Failed to connect to broken-svc:80 after 40 ms: Could not connect to server
command terminated with exit code 7
```

Note **`after 40 ms`** — an immediate refusal, not a timeout. As in Topic 03, that distinction is
diagnostic: DNS resolved fine (the Service exists) and the connection was rejected at once because
there is no backend to forward to. A timeout would have pointed at a NetworkPolicy or firewall
instead.

### Diagnosis, by comparing the two label sets

```console
$ kubectl get svc broken-svc -o jsonpath='{.spec.selector}'
{"app":"whoami-typo"}

$ kubectl get pods -l app=whoami --show-labels --no-headers | head -1
whoami-ff5dbf989-bwd27   1/1   Running   0   2m8s   app=whoami,owner=dhruv,pod-template-hash=ff5dbf989

$ kubectl get pods -l app=whoami-typo
No resources found in default namespace.
```

That last command is the cleanest test available: **run the Service's own selector as a `kubectl get
pods -l` query.** If it returns nothing, the Service will have no endpoints — no further
investigation needed.

### The fix

```console
$ kubectl patch svc broken-svc -p '{"spec":{"selector":{"app":"whoami"}}}'
service/broken-svc patched

$ kubectl get endpoints broken-svc
NAME         ENDPOINTS                                      AGE
broken-svc   10.244.1.35:80,10.244.1.36:80,10.244.1.37:80   9s

$ kubectl exec client -- curl -s http://broken-svc
served by pod whoami-ff5dbf989-bwd27
```

Endpoints appeared within seconds of the patch, with no Pod restart — the controller reconciled the
new selector immediately.

### Other causes of empty endpoints

| Cause | How to spot it |
|---|---|
| Selector typo / wrong labels | `kubectl get pods -l <selector>` returns nothing |
| Pods exist but are not **Ready** | Only ready Pods are endpoints — check `READY 0/1` and the readiness probe |
| `targetPort` does not match `containerPort` | Endpoints exist but connections are refused |
| Service in a different namespace than the Pods | Selectors never cross namespaces |
| Pods still `Pending` / `ImagePullBackOff` | The Topic 09 statuses — nothing is ready yet |

The second row is the subtle one: a failing readiness probe removes a Pod from the endpoint list
while leaving it `Running`. That is a feature — it is how rolling updates avoid sending traffic to a
half-started Pod — but it looks like an endpoints bug.

---

## Service type summary

| Type | ClusterIP? | Reachable from | Use for |
|---|---|---|---|
| **ClusterIP** | Yes | Inside the cluster only | Internal service-to-service. The default |
| **NodePort** | Yes | `<anyNodeIP>:30000-32767` | Dev access; plumbing under a LoadBalancer |
| **LoadBalancer** | Yes (+ NodePort) | A cloud external IP | Public services on a cloud provider |
| **ExternalName** | **No** | DNS CNAME only | Aliasing an external hostname |
| **Headless** (`clusterIP: None`) | **No** | All Pod IPs via DNS | StatefulSets, per-Pod addressing |

For many HTTP services on one IP, none of these is the right answer — that is Ingress, in Topic 11.

---

## Clean up

```console
$ kubectl delete -f manifests/ --recursive
$ kubectl delete pod client
$ kubectl delete svc broken-svc
```
