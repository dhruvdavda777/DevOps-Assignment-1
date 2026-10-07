# CoreDNS – Cluster DNS and Service Discovery

**Name:** Dhruv Davda · **Roll No:** 24BCS10203 · **Email:** Dhruv.24bcs10203@sst.scaler.com · **Group:** A

Session 11, Task 4. Run against my `dhruv-devops` kind cluster (CoreDNS v1.14.6).

## What is CoreDNS?

CoreDNS is a general-purpose DNS server written in Go, and since Kubernetes 1.13 it is the **default
cluster DNS**. It is not a Kubernetes-specific product: it is a DNS server with a **plugin chain**,
one of whose plugins happens to understand the Kubernetes API.

The critical thing to internalise: **CoreDNS is just a workload running inside the cluster it
serves.** It is a Deployment and a Service like anything else:

```console
$ kubectl get deploy -n kube-system -l k8s-app=kube-dns
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
coredns   2/2     2            2           11m

$ kubectl get svc -n kube-system -l k8s-app=kube-dns -o wide
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE   SELECTOR
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   11m   k8s-app=kube-dns

$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE
coredns-559f6c778d-grwdf   1/1     Running   0          11m   10.244.0.3   dhruv-devops-control-plane
coredns-559f6c778d-rhg46   1/1     Running   0          11m   10.244.0.4   dhruv-devops-control-plane
```

Two observations:

- The Service is still named **`kube-dns`** even though CoreDNS replaced kube-dns years ago. The name
  was kept so that every Pod's `/etc/resolv.conf` (`nameserver 10.96.0.10`) kept working.
- **2 replicas**, because DNS is a single point of failure for the entire cluster. Every Pod's
  outbound connection starts with a DNS query.

```console
$ kubectl get deploy coredns -n kube-system -o jsonpath='image={...image} replicas={.spec.replicas}'
image=registry.k8s.io/coredns/coredns:v1.14.6 replicas=2
```

## Why Kubernetes uses CoreDNS

It replaced `kube-dns` (which was three containers: `kube-dns`, `dnsmasq` and `sidecar`) because:

| | kube-dns | CoreDNS |
|---|---|---|
| Processes | 3 containers | **1** |
| Config | Flags across components | **One Corefile** |
| Extensibility | Hard | **Plugin chain** |
| Memory | Higher | Lower |
| Known issues | dnsmasq CVEs, cache bugs | Simpler surface |

The deciding factor was the plugin architecture: features like rewriting, per-zone forwarding and
custom stub domains are plugin lines rather than patches.

## Configuration: the Corefile

CoreDNS's entire configuration is one ConfigMap:

```console
$ kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30 {
       disable success cluster.local
       disable denial cluster.local
    }
    loop
    reload
    loadbalance
}
```

Line by line, because every one of these does something observable:

| Directive | What it does |
|---|---|
| `.:53` | Serve **all** zones (`.`) on port 53 |
| `errors` | Log errors to stdout |
| `health` + `lameduck 5s` | `/health` endpoint; on shutdown keep reporting healthy for 5s so in-flight queries drain |
| `ready` | `/ready` endpoint — the readiness probe, so a starting Pod gets no queries |
| `kubernetes cluster.local in-addr.arpa ip6.arpa` | **The Kubernetes plugin.** Watches the API for Services/Endpoints and answers for these zones. `in-addr.arpa` is what makes reverse lookups work |
| `pods insecure` | Enables `<ip>.<ns>.pod.cluster.local` records |
| `ttl 30` | Records are cached by clients for 30s |
| `prometheus :9153` | Metrics endpoint |
| `forward . /etc/resolv.conf` | **Anything not `cluster.local` goes upstream**, to the node's own resolver |
| `cache 30` | Cache answers for 30s |
| `loop` | Detects a forwarding loop and crashes deliberately rather than melting down |
| `reload` | Watch the ConfigMap and apply changes **without a restart** |
| `loadbalance` | Shuffle A records so clients spread across them |

`reload` is why editing the ConfigMap is enough to change DNS behaviour — the log confirms it:

```console
$ kubectl logs -n kube-system -l k8s-app=kube-dns --tail=6 --prefix
[pod/coredns-559f6c778d-grwdf/coredns] .:53
[pod/coredns-559f6c778d-grwdf/coredns] [INFO] plugin/reload: Running configuration SHA512 = 1b226df79860026c6a52e67daa10d7f0d57ec5b023288ec00c5e05f93523c894564e15b917...
[pod/coredns-559f6c778d-grwdf/coredns] CoreDNS-1.14.6
[pod/coredns-559f6c778d-grwdf/coredns] linux/arm64, go1.26.5, 424d125
```

Note there are **no query logs**. The `log` plugin is deliberately absent by default — logging every
DNS query in a busy cluster is enormous volume. Adding `log` to the Corefile turns it on, which is
the first step when debugging intermittent resolution failures.

## How service discovery works

1. A Service is created. The API server assigns it a ClusterIP.
2. CoreDNS's `kubernetes` plugin holds a **watch** on the API server, so it learns immediately — it
   does not poll, and records are not written to a zone file anywhere.
3. A Pod queries `web.team-a.svc.cluster.local`.
4. The query goes to `10.96.0.10` (from the Pod's `/etc/resolv.conf`), which is a normal ClusterIP —
   **so kube-proxy DNATs it to one of the two CoreDNS Pods.**
5. The `kubernetes` plugin matches the `cluster.local` zone and answers from its watch cache.
6. A name outside the zone falls through to `forward`, which sends it to the node's upstream resolver.

Step 4 has a consequence worth stating: **DNS itself depends on kube-proxy working.** If Service
networking breaks, DNS breaks with it, and nearly everything then looks like a DNS problem.

## How DNS queries are resolved

Resolution is driven by the Pod's resolver config:

```console
$ kubectl exec client -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

`ndots:5` means a name with fewer than 5 dots gets the `search` suffixes appended **first**. Full
details and the `dig`-vs-application trap are in [`../fqdn/README.md`](../fqdn/README.md).

### Measuring what ndots actually costs

I measured it against CoreDNS's own counters, scraping each Pod directly:

```console
$ kubectl exec client -- curl -s http://10.244.0.3:9153/metrics | grep '^coredns_dns_requests_total'
coredns_dns_requests_total{...,type="A",...} 255
coredns_dns_requests_total{...,type="AAAA",...} 437
coredns_dns_requests_total{...,type="SRV",...} 2
```

20 lookups each way:

```console
baseline (both pods): 1291
after 20x SHORT    'web.team-a':                   1411   (delta 120)
after 20x ABSOLUTE 'web.team-a.svc.cluster.local.': 1471   (delta  60)

  short name    :  120 queries / 20 lookups = 6.00 per lookup
  absolute name :   60 queries / 20 lookups = 3.00 per lookup
  -> trailing dot reduced DNS query volume by 50%
```

**A single trailing dot halved the DNS traffic.** The short name needs the search list walked until
a suffix hits; the absolute name is answered on the first try. Both are multiplied by roughly two
because the resolver asks for **A and AAAA** on every lookup — visible in the raw counters above,
where AAAA (437) actually exceeds A (255) despite this cluster being IPv4-only.

That AAAA-exceeds-A ratio is a well-known Kubernetes inefficiency, and together with ndots it is why
busy clusters sometimes need NodeLocal DNSCache.

### A measurement mistake worth recording

My first attempt scraped the metrics through the **`kube-dns` Service VIP** and produced a *negative*
delta — a count going down over time, which is impossible for a counter:

```console
baseline request count: 509
after short-name lookups: 479   -> delta = -30 queries for 20 lookups
```

The cause: the VIP load-balances across **two** CoreDNS Pods with independent counters, so successive
scrapes hit different Pods. **Per-instance metrics must be scraped per instance**, which is exactly
why Prometheus discovers and scrapes individual Pods rather than Services.

## Troubleshooting DNS issues

### The order I would work through

```bash
# 1. Is CoreDNS even running?
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# 2. Does the Service have endpoints? (DNS depends on kube-proxy)
kubectl get svc,endpoints -n kube-system kube-dns

# 3. What does the Pod think its resolver is?
kubectl exec <pod> -- cat /etc/resolv.conf

# 4. Resolve the way an APPLICATION does, not the way dig does
kubectl exec <pod> -- getent hosts <service>.<ns>.svc.cluster.local

# 5. Ask CoreDNS directly, bypassing the Service VIP
kubectl exec <pod> -- dig @10.244.0.3 web.team-a.svc.cluster.local

# 6. Does the target Service have endpoints of its own?
kubectl get endpoints <service> -n <ns>

# 7. Turn on query logging: add `log` to the Corefile, then
kubectl logs -n kube-system -l k8s-app=kube-dns -f
```

Step 4 matters more than it looks — a bare `dig` ignores the `search` list and will report
`NXDOMAIN` for a short name that applications resolve perfectly.

### Common causes

| Symptom | Likely cause | Check |
|---|---|---|
| Nothing resolves anywhere | CoreDNS Pods down / not Ready | `kubectl get pods -n kube-system` |
| Short names fail, FQDNs work | Wrong namespace assumed in `search` | `cat /etc/resolv.conf` |
| Name resolves, connection refused | **Not DNS** — Service has no endpoints | `kubectl get endpoints` |
| Only external names fail | `forward` upstream unreachable | Node's own `/etc/resolv.conf` |
| Intermittent timeouts under load | DNS throttling / conntrack races | CoreDNS metrics; consider NodeLocal DNSCache |
| CoreDNS `CrashLoopBackOff` with "Loop detected" | `forward` pointing back at itself | The `loop` plugin's log message |
| High DNS latency, huge query volume | `ndots:5` search-list amplification | Measure as above; use FQDNs or lower ndots |

The third row is the one that wastes the most time: **"I can't reach my service" is usually not a DNS
problem.** Resolution succeeding while connections fail points at endpoints or a NetworkPolicy, not
at CoreDNS — the empty-endpoints case demonstrated in the main Topic 10 README.

### Tuning ndots per Pod

Where an app makes heavy use of external names, the search-list walk can be skipped per Pod:

```yaml
spec:
  dnsConfig:
    options:
      - name: ndots
        value: "2"
```

The trade-off: short cross-namespace names like `web.team-a` (1 dot) would then be queried absolutely
and fail, so this needs FQDNs in configuration. For most workloads the simpler fix is the trailing
dot measured above.

## Summary

- CoreDNS is an ordinary Deployment behind the `kube-dns` ClusterIP `10.96.0.10`, configured by a
  single Corefile ConfigMap, with `reload` applying changes without a restart.
- The `kubernetes` plugin watches the API server, so Service records appear the moment a Service is
  created.
- `ndots:5` makes short names convenient and expensive — **measured here at 2× the query volume** of
  a fully qualified name with a trailing dot.
- Because DNS resolution rides on a ClusterIP, DNS depends on kube-proxy; and because resolution
  succeeding proves nothing about connectivity, always check endpoints before blaming DNS.
