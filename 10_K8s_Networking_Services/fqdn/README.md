# FQDN – Fully Qualified Domain Names in Kubernetes

**Name:** Dhruv Davda · **Roll No:** 24BCS10203 · **Email:** Dhruv.24bcs10203@sst.scaler.com · **Group:** A

Session 11, Task 3. Everything below was run against my `dhruv-devops` kind cluster, using two
namespaces (`team-a`, `team-b`) that each contain a Service called **`web`** — deliberately the same
name, to show how namespaces keep them apart.

## What is an FQDN?

A **fully qualified domain name** is a name written out completely, all the way to the root — leaving
nothing for the resolver to guess. `web` is ambiguous; `web.team-a.svc.cluster.local.` is not.

```
web            .team-a        .svc          .cluster.local
└─ service     └─ namespace   └─ record     └─ cluster domain
                                 type
```

The practical difference: a **partial name** is completed by the resolver using the `search` list in
`/etc/resolv.conf`, so its meaning depends on *where it is resolved from*. An FQDN resolves to the
same thing everywhere.

## Kubernetes DNS naming convention

| Object | Pattern | Example |
|---|---|---|
| Service | `<svc>.<ns>.svc.<cluster-domain>` | `web.team-a.svc.cluster.local` |
| Headless Service member | `<pod>.<svc>.<ns>.svc.<domain>` | `db-0.db-headless.default.svc.cluster.local` |
| Pod (by IP) | `<ip-with-dashes>.<ns>.pod.<domain>` | `10-244-1-37.team-a.pod.cluster.local` |
| SRV record | `_<port-name>._<proto>.<svc>.<ns>.svc.<domain>` | `_http._tcp.web.team-a.svc.cluster.local` |

`cluster.local` is the default cluster domain, set at cluster creation.

## The search list is what makes short names work

```console
$ kubectl exec client -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

Three fields, each doing real work:

- **`search`** — suffixes tried in order for a name that is not already fully qualified. This Pod is
  in `default`, so its own namespace comes first.
- **`nameserver 10.96.0.10`** — the `kube-dns` Service ClusterIP (CoreDNS).
- **`options ndots:5`** — if a name contains **fewer than 5 dots**, try the search list *first*, and
  only query it as an absolute name if all of those fail.

`ndots:5` is the setting behind most Kubernetes DNS surprises. `web.team-a.svc.cluster.local` has 4
dots — still under 5 — so even that gets the search suffixes appended first:

```
web.team-a.svc.cluster.local.default.svc.cluster.local   -> NXDOMAIN
web.team-a.svc.cluster.local.svc.cluster.local           -> NXDOMAIN
web.team-a.svc.cluster.local.cluster.local               -> NXDOMAIN
web.team-a.svc.cluster.local                             -> 10.96.140.93  ✓
```

**Four queries to resolve one name.** Writing it with a trailing dot — `web.team-a.svc.cluster.local.`
— marks it as already absolute and skips straight to the answer. The measured cost of this is in
[`../coredns/README.md`](../coredns/README.md).

## A trap: `dig` does not behave like your application

This caught me out, and it is worth recording because it would have led to a wrong conclusion.

```console
=== A. dig WITHOUT the search list (dig's default: query the name verbatim) ===
  dig web.team-a                     -> (no answer)
  dig web.team-a.svc                 -> (no answer)
  dig web.team-a.svc.cluster.local   -> 10.96.140.93
```

Read alone, that says the short forms are broken. They are not — **`dig` queries the name exactly as
typed and ignores the `search` list by default.** Applications use the libc resolver, which does not:

```console
=== B. dig +search (apply resolv.conf search list, like an app does) ===
  dig +search web.team-a             -> 10.96.140.93
  dig +search web.team-a.svc         -> 10.96.140.93

=== C. getent — the libc resolver an application actually uses ===
  getent hosts web.team-a                   -> 10.96.140.93  web.team-a.svc.cluster.local
  getent hosts web.team-a.svc               -> 10.96.140.93  web.team-a.svc.cluster.local
  getent hosts web.team-a.svc.cluster.local -> 10.96.140.93  web.team-a.svc.cluster.local

=== D. curl — the decisive test ===
  curl http://web.team-a                       -> HTTP 200
  curl http://web.team-a.svc                   -> HTTP 200
  curl http://web.team-a.svc.cluster.local     -> HTTP 200
  curl http://web.team-b.svc.cluster.local     -> HTTP 200
```

Note `getent` resolving every form back to the **same canonical FQDN** — that is the search list
being applied and the answer being completed.

**Rule I took from this: debug Kubernetes DNS with `getent hosts` or `nslookup`, not bare `dig`.**
Use `dig +search` when you want dig to behave like the application. Bare `dig` is still the right
tool for asking "does this exact record exist?".

## Namespace-based DNS

Both namespaces have a Service literally called `web`:

```console
$ kubectl get svc -A | grep -E 'NAMESPACE|team-'
NAMESPACE   NAME   TYPE        CLUSTER-IP      PORT(S)   AGE
team-a      web    ClusterIP   10.96.140.93    80/TCP    1s
team-b      web    ClusterIP   10.96.135.177   80/TCP    1s

$ kubectl exec client -- dig +short web.team-a.svc.cluster.local
10.96.140.93
$ kubectl exec client -- dig +short web.team-b.svc.cluster.local
10.96.135.177
```

Different IPs, same short name — the namespace is the disambiguator.

And the search list makes the **bare name relative to the caller**:

```console
$ kubectl -n team-a exec c2 -- cat /etc/resolv.conf | head -1
search team-a.svc.cluster.local svc.cluster.local cluster.local
```

A Pod in `team-a` has `team-a.svc.cluster.local` first, so `web` means *its own* namespace's Service.
The identical application config deployed to `team-b` would reach `team-b`'s `web` instead — with no
change. That is how one manifest serves dev, staging and prod namespaces.

## Pod-to-Service communication

What actually happens when a Pod calls `http://web.team-a`:

1. The app calls `getaddrinfo("web.team-a")`.
2. libc reads `/etc/resolv.conf`: fewer than 5 dots → walk the `search` list.
3. Query `web.team-a.default.svc.cluster.local` → NXDOMAIN.
4. Query `web.team-a.svc.cluster.local` → **`10.96.140.93`**.
5. The app opens a TCP connection to that ClusterIP.
6. **kube-proxy's iptables/IPVS rules DNAT it** to one of the backing Pod IPs.
7. The packet reaches a Pod on the CNI network.

Steps 1–4 are DNS; steps 5–7 are not. **DNS resolves the Service to its ClusterIP and stops there** —
it never returns a Pod IP for a normal Service, and it does no load balancing. That happens in the
kernel. This is exactly why a Service with a bad selector still *resolves* perfectly while every
connection is refused: the "empty endpoints" failure from the main Topic 10 README.

The exception is a **headless Service** (`clusterIP: None`), where DNS returns the Pod IPs directly
and the client chooses — demonstrated in the main README.

## Examples of Kubernetes FQDNs

### SRV records — discovering the port, not just the host

SRV records only exist when the Service port is **named**:

```console
$ kubectl -n team-a get svc web -o jsonpath='{.spec.ports[0].name}'
http

$ kubectl exec client -- dig +short SRV _http._tcp.web.team-a.svc.cluster.local
0 100 80 web.team-a.svc.cluster.local.
```

The fields are priority `0`, weight `100`, **port `80`**, target. A client can discover the port
rather than hard-coding it.

The contrast proves the rule — `team-b`'s port was created unnamed by `kubectl expose`:

```console
$ kubectl -n team-b get svc web -o jsonpath='{.spec.ports[0].name}'
(empty)
$ kubectl exec client -- dig +short SRV _http._tcp.web.team-b.svc.cluster.local
(no SRV record)
```

**Naming your Service ports costs nothing and enables SRV discovery.**

### Reverse lookup

```console
$ kubectl exec client -- dig +short -x 10.96.140.93
web.team-a.svc.cluster.local.
```

PTR records map ClusterIPs back to names — which is why `in-addr.arpa` appears in the CoreDNS
Corefile. Useful when a log line contains an IP and you need to know which Service it was.

### Pod DNS

```console
$ kubectl exec client -- dig +short 10-244-1-37.team-a.pod.cluster.local
10.244.1.37
```

Every Pod IP gets an A record under `.pod.cluster.local`, with dots replaced by dashes. Rarely used
directly, since Pod IPs are unstable, but it exists.

### External names

```console
$ kubectl exec client -- dig +short github.com
20.207.73.82
```

Anything outside `cluster.local` is forwarded upstream by CoreDNS's `forward` plugin — so in-cluster
and internet DNS both work through the same resolver.

## Quick reference

| From | To reach `web` in `team-a` | Works? |
|---|---|---|
| Pod in `team-a` | `web` | Yes — own namespace is first in `search` |
| Pod in `default` | `web` | **No** — resolves to `web.default...`, which does not exist |
| Pod in `default` | `web.team-a` | Yes |
| Pod in `default` | `web.team-a.svc.cluster.local` | Yes — unambiguous, preferred in config |
| Anywhere | `web.team-a.svc.cluster.local.` | Yes, and **fastest** (trailing dot skips the search list) |

**Practical advice:** use the bare Service name for same-namespace calls (it keeps manifests portable
across environments), and the full FQDN for cross-namespace calls and anything in a config file,
where ambiguity is a bug waiting to happen.
