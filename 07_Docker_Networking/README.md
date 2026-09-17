# Topic 07 – Docker Networking and Volumes

**Name:** Dhruv Davda
**Roll No:** 24BCS10203
**Email:** Dhruv.24bcs10203@sst.scaler.com
**Group:** A

---

## Task 1: Docker container networking

### Design

Two user-defined bridge networks, to test both connectivity *and* isolation:

```
   frontend-net (172.20.0.0/16)          backend-net (10.55.0.0/24)
   ┌───────────────────────────┐         ┌──────────────────────────┐
   │  web-a          web-b     │         │   db-only                │
   │  172.20.0.2     172.20.0.3│         │   10.55.0.2              │
   └───────────────────────────┘         └──────────────────────────┘
              web-a is later attached to BOTH networks (10.55.0.3)
```

### Create the networks and containers

```console
$ docker network create frontend-net
f1ebdc78783ffd901a8679a6c4ddcd276a25ea7e228bb0c45854cf72326d37de

$ docker network create --subnet 10.55.0.0/24 backend-net
5eb59cba59bc35e49ff8bb3528f4dc89fe161059364fb998cffa27dba120aca7

$ docker network ls
NETWORK ID     NAME           DRIVER    SCOPE
5eb59cba59bc   backend-net    bridge    local
b261c3384b16   bridge         bridge    local
f1ebdc78783f   frontend-net   bridge    local
58cdc59ea4fe   host           host      local
7829d33a387f   kind           bridge    local
26385f2003f5   none           null      local
```

```console
$ docker run -d --name web-a   --network frontend-net nginx:1.27-alpine
$ docker run -d --name web-b   --network frontend-net nginx:1.27-alpine
$ docker run -d --name db-only --network backend-net  nginx:1.27-alpine

$ docker ps --format "table {{.Names}}\t{{.Networks}}\t{{.Status}}"
NAMES     NETWORKS       STATUS
db-only   backend-net    Up Less than a second
web-b     frontend-net   Up Less than a second
web-a     frontend-net   Up Less than a second

$ docker network inspect frontend-net \
    --format '{{range .IPAM.Config}}{{.Subnet}}{{end}} | {{range .Containers}}{{.Name}}={{.IPv4Address}} {{end}}'
172.20.0.0/16 | web-a=172.20.0.2/16 web-b=172.20.0.3/16

$ docker network inspect backend-net \
    --format '{{range .IPAM.Config}}{{.Subnet}}{{end}} | {{range .Containers}}{{.Name}}={{.IPv4Address}} {{end}}'
10.55.0.0/24 | db-only=10.55.0.2/24
```

Docker picked `172.20.0.0/16` for `frontend-net` automatically; `backend-net` got the `/24` I asked
for with `--subnet`.

### Check connectivity — same network

```console
$ docker exec web-a ping -c 3 web-b
PING web-b (172.20.0.3): 56 data bytes
64 bytes from 172.20.0.3: seq=0 ttl=64 time=0.547 ms
64 bytes from 172.20.0.3: seq=1 ttl=64 time=0.164 ms
64 bytes from 172.20.0.3: seq=2 ttl=64 time=0.144 ms

--- web-b ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.144/0.285/0.547 ms

$ docker exec web-a nslookup web-b | tail -3
Non-authoritative answer:
Name:	web-b
Address: 172.20.0.3

$ docker exec web-a wget -qO- http://web-b | grep -o '<title>.*</title>'
<title>Welcome to nginx!</title>
```

The container name resolved to an IP and HTTP worked — **on a user-defined network Docker runs an
embedded DNS server at 127.0.0.11 that resolves container names automatically.**

### Check connectivity — across networks

```console
$ docker exec web-a ping -c 2 -W 2 db-only
ping: bad address 'db-only'

$ docker exec web-a wget -qO- --timeout=3 http://10.55.0.2
wget: download timed out
```

Two *different* failures, which is the interesting part:

- `bad address` is a **DNS** failure — `db-only` is not in `web-a`'s DNS scope at all.
- Bypassing DNS with the raw IP gives a **timeout**, not "bad address". The name is gone *and* the
  route is blocked. Isolation is enforced at the network layer, not just by hiding names.

### The default bridge behaves differently

```console
$ docker run -d --name legacy-a nginx:1.27-alpine   # no --network, so default bridge
$ docker run -d --name legacy-b nginx:1.27-alpine

$ docker exec legacy-a ping -c 2 -W 2 legacy-b
ping: bad address 'legacy-b'
```

**On the default `bridge` network there is no automatic DNS.** The containers share a subnet and can
reach each other by IP, but not by name. This is the single best reason to always create a
user-defined network: names are stable, IPs are not.

### Attaching one container to both networks

```console
$ docker network connect backend-net web-a

$ docker inspect web-a --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}'
backend-net=10.55.0.3 frontend-net=172.20.0.2

$ docker exec web-a ip -4 addr show | grep inet
    inet 127.0.0.1/8 scope host lo
    inet 172.20.0.2/16 brd 172.20.255.255 scope global eth0
    inet 10.55.0.3/24 brd 10.55.0.255 scope global eth1

$ docker exec web-a ping -c 3 db-only
PING db-only (10.55.0.2): 56 data bytes
64 bytes from 10.55.0.2: seq=0 ttl=64 time=2.532 ms
64 bytes from 10.55.0.2: seq=1 ttl=64 time=0.174 ms
64 bytes from 10.55.0.2: seq=2 ttl=64 time=0.243 ms

--- db-only ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
```

`web-a` gained a **second interface, `eth1`**, and a second IP. And critically, `web-b` did not:

```console
$ docker exec web-b ping -c 2 -W 2 db-only
ping: bad address 'db-only'
```

### Result

| From → to | Same network | Result |
|---|---|---|
| `web-a` → `web-b` (by name) | yes | ping + DNS + HTTP all work |
| `web-a` → `db-only` (by name) | no | `bad address` — DNS scoped per network |
| `web-a` → `10.55.0.2` (by IP) | no | timeout — routing blocked too |
| `legacy-a` → `legacy-b` (default bridge) | yes | `bad address` — no DNS on the default bridge |
| `web-a` → `db-only` after `network connect` | both | works, via new `eth1` |
| `web-b` → `db-only` after that | no | still blocked |

### What I understood

- **A user-defined bridge network is the unit of isolation and of service discovery.** Membership
  decides both who you can reach and whose names you can resolve.
- Multi-homing a single container onto two networks is the **DMZ / reverse-proxy pattern**: exactly
  what the nginx container did in my Topic 06 three-tier app, where it sat between the published
  port and a database that was never exposed. `web-b` staying blocked is the proof the pattern
  actually contains traffic.
- **Never hardcode container IPs.** `web-a` was `172.20.0.2` this run; recreate it and it may not
  be. The name is the stable address.
- `docker network inspect --format` with `{{range .Containers}}` is a quick way to see exactly who is
  on a network, without reading a page of JSON.

---

## Task 2: Host network

```console
$ docker run -d --name host-web --network host nginx:1.27-alpine
65d9a9d5c5f51fbb151c0889f731574c5b86db3bcaf85e95ed54ad706bddc516

$ docker ps --filter name=host-web --format "table {{.Names}}\t{{.Networks}}\t{{.Ports}}\t{{.Status}}"
NAMES      NETWORKS   PORTS     STATUS
host-web   host                 Up 2 seconds
```

The **`PORTS` column is empty** — with `--network host` there is nothing to map, because the
container is not in its own network namespace.

### It failed, and the error is the lesson

```console
$ curl -s -o /dev/null -w "status=%{http_code}\n" --max-time 5 http://localhost:80
status=000

$ docker ps -a --filter name=host-web --format '{{.Names}} {{.Status}}'
host-web Exited (1) 40 seconds ago

$ docker logs host-web
2026/09/17 15:24:15 [emerg] 1#1: bind() to 0.0.0.0:80 failed (98: Address in use)
nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address in use)
2026/09/17 15:24:15 [notice] 1#1: try again to bind() after 500ms
2026/09/17 15:24:15 [emerg] still could not bind()
```

**`Address in use`.** My kind cluster from Topic 08 publishes host ports 80 and 443:

```console
$ docker ps --filter publish=80 --format '{{.Names}} {{.Ports}}'
dhruv-devops-control-plane 0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 127.0.0.1:54929->6443/tcp
```

This is the defining drawback of host networking: **there is no port namespace, so the container
competes with every other process for ports.** In bridge mode I ran six containers all listening on
container port 80 in Topic 05 without a single clash, because each had its own namespace.

### Retrying on a free port

```console
$ docker run -d --name host-web --network host python:3.12-alpine python -m http.server 8092
c22e6819387307960dfe5ef4061294b8e836d3a020328fb00950c9e11fa1bd45

$ docker ps --filter name=host-web --format "table {{.Names}}\t{{.Networks}}\t{{.Ports}}\t{{.Status}}"
NAMES      NETWORKS   PORTS     STATUS
host-web   host                 Up 3 seconds
```

### An important detail on macOS

```console
$ docker exec host-web hostname
docker-desktop

$ docker exec host-web ip -4 addr show | grep inet
    inet 127.0.0.1/8 scope host lo
    inet 192.168.65.3/24 brd 192.168.65.255 scope global eth0
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
    inet 172.18.0.1/16 brd 172.18.255.255 scope global br-33af7c57ba00
    inet 172.19.0.1/16 brd 172.19.255.255 scope global br-7829d33a387f
    inet 172.20.0.1/16 brd 172.20.255.255 scope global br-f1ebdc78783f
    inet 10.55.0.1/24 brd 10.55.0.255 scope global br-5eb59cba59bc
```

The hostname is **`docker-desktop`, not my Mac**, and the interfaces include `docker0` and the
bridge interfaces `br-f1ebdc78783f` (my `frontend-net`, gateway `172.20.0.1`) and `br-5eb59cba59bc`
(my `backend-net`, gateway `10.55.0.1`).

So "host" means **the Linux VM that Docker Desktop runs, not macOS.** Containers cannot share a
macOS network namespace because macOS is not Linux. Testing from both sides proves it:

```console
# from inside the VM's network namespace
$ docker run --rm --network host alpine:3.20 sh -c 'apk add -q curl && \
    curl -s -o /dev/null -w "VM localhost:8092 -> %{http_code}\n" http://localhost:8092'
VM localhost:8092 -> 200

# from macOS itself
$ curl -s -o /dev/null -w "mac localhost:8092 -> %{http_code}\n" --max-time 5 http://localhost:8092
mac localhost:8092 -> 000

$ docker logs host-web | tail -1
127.0.0.1 - - [17/Sep/2026 15:25:22] "GET / HTTP/1.1" 200 -
```

**200 from inside the VM, nothing from the Mac.** The server is working perfectly; it is simply on a
network my laptop cannot reach, because `--network host` deliberately skips the port forwarding that
would have bridged the two. A bridge container with `-p` is reachable as normal:

```console
$ docker run -d --name bridge-web -p 8091:80 nginx:1.27-alpine
$ curl -s -o /dev/null -w "status=%{http_code}\n" http://localhost:8091
status=200
```

And host networking really does give VM-level reach — it can hit my bridge containers' IPs directly,
with no published ports at all:

```console
$ docker run --rm --network host alpine:3.20 sh -c 'apk add -q curl && \
    curl -s -o /dev/null -w "web-a=%{http_code}\n" http://172.20.0.2'
web-a=200
```

### What I understood

| | Bridge (default) | Host |
|---|---|---|
| Network namespace | Its own | Shared with the host |
| `-p` port mapping | Required and possible | Ignored, impossible |
| Port conflicts | None, each container isolated | Competes with every host process |
| Performance | NAT adds a small overhead | No NAT, marginally faster |
| Container-to-container DNS | Yes, on user-defined networks | No, it is not on a Docker network |
| Works on macOS as expected | Yes | **No** — "host" is the Docker Desktop VM |

Host networking is for the narrow cases that actually need it: very high throughput where NAT
overhead matters, or software that must see the real host interfaces (monitoring agents,
`node_exporter`, anything doing network discovery). For normal applications, bridge plus `-p` is
better — and on macOS, host networking is close to useless for anything you want to open in a
browser.

---

## Task 3: Bind mount

```console
$ pwd
/Users/dhruv/Desktop/DevOps-Assignment/07_Docker_Networking/bind-mount

$ grep '<h1>' index.html
  <h1>Version 1 - served from a bind mount</h1>

$ docker run -d --name bind-web -p 8093:80 -v "$PWD":/usr/share/nginx/html:ro nginx:1.27-alpine
a0b1fd1e6c33c362bea6f8830da046bf8c9fb2b54f6878437cc642a1ff96f21b

$ curl -s http://localhost:8093 | grep -E '<h1>|24BCS'
  <h1>Version 1 - served from a bind mount</h1>
  <p>Dhruv Davda &middot; 24BCS10203 &middot; Group A</p>
```

nginx is serving a file that is **not in the image** — it is on my Mac's filesystem.

### Editing the file live

```console
$ sed -i '' 's/Version 1 - served from a bind mount/Version 2 - edited live on the host/' index.html
$ grep '<h1>' index.html
  <h1>Version 2 - edited live on the host</h1>

$ curl -s http://localhost:8093 | grep -E '<h1>|Edited at'
  <h1>Version 2 - edited live on the host</h1>
  <p>Edited at 20:55:42 with no rebuild and no restart.</p>
```

**No rebuild, no restart, no `docker cp`.** The change was visible on the very next request.

![bind mount after the live edit](./screenshots/d07-04-bind-mount-after-edit.png)

*(The screenshot shows the post-edit state; the `curl` transcript above captures both versions.)*

### The `:ro` flag is enforced

```console
$ docker exec bind-web sh -c 'echo hacked > /usr/share/nginx/html/index.html'
sh: can't create /usr/share/nginx/html/index.html: Read-only file system

$ docker inspect bind-web --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}} rw={{.RW}}{{end}}'
bind /Users/dhruv/Desktop/DevOps-Assignment/07_Docker_Networking/bind-mount -> /usr/share/nginx/html rw=false
```

The container can read my directory but cannot modify it. For a web server serving static content
that is exactly right — a compromised nginx cannot rewrite my source files.

### What I understood

- **A bind mount maps a host path into the container**, and the host wins: whatever is at that path
  replaces the image's contents at the mount point. Anything the image had at
  `/usr/share/nginx/html` is hidden while the mount is active.
- It is the standard **development** workflow. Editing source and refreshing the browser beats a
  rebuild-and-restart cycle. For **production** the file should be baked into the image instead, as
  in Topic 05 — otherwise the image is not self-contained and the deployment depends on the host
  having the right files.
- `:ro` costs nothing and should be the default for anything the container only needs to read.

### Bind mount vs named volume

| | Bind mount | Named volume |
|---|---|---|
| Location | A path I choose on the host | Managed by Docker in `/var/lib/docker/volumes` |
| Syntax | `-v /host/path:/container/path` | `-v myvol:/container/path` |
| Host can edit directly | Yes, that is the point | Not conveniently |
| Portable across machines | No, depends on the host path | Yes |
| Best for | Source code in development, config files | Databases and application state |

This is not theoretical — in Topic 06 the Postgres tier used a **named volume**, and the visit count
survived a full `docker compose down` and `up`. A bind mount would have worked too, but the data's
location would then have been my laptop's directory layout rather than something Docker manages.

---

## Task 4: Overlay network

Rather than only reading about it, I created a real overlay network by putting my single Docker
engine into swarm mode.

### What it is

A **bridge network spans one host. An overlay network spans many.** It lets containers on different
physical machines sit on one flat virtual subnet and talk by name, as if they were on the same
bridge.

### How it works across hosts

1. The hosts join a **swarm** (or another cluster manager). A distributed key-value store keeps the
   network state in sync.
2. Docker creates a **VXLAN tunnel** between the hosts. VXLAN encapsulates each layer-2 frame inside
   a UDP packet (port **4789**) and sends it to the peer host, which unwraps it. The containers see a
   normal LAN; the physical network only sees UDP.
3. A per-network **VNI** (VXLAN Network Identifier) keeps separate overlay networks from mixing.
4. Swarm's DNS resolves service names to a **VIP**, and load-balances across the tasks behind it.

Ports that must be open between hosts: **2377/tcp** (cluster management), **7946/tcp+udp** (node
discovery), **4789/udp** (the VXLAN data plane).

### Commands, and what they produced on my machine

```console
$ docker swarm init
Swarm initialized: current node (agblwoktq75g5w7tg7gn1fsnx) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-<token redacted> 192.168.65.3:2377

$ docker network create -d overlay --attachable app-overlay
wugw2l7o7kigsixucj4lw447s

$ docker network ls --filter driver=overlay
NETWORK ID     NAME          DRIVER    SCOPE
wugw2l7o7kig   app-overlay   overlay   swarm
zapde8qa9pmz   ingress       overlay   swarm
```

The **`SCOPE` column is the whole difference**:

```console
$ docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
NAME           DRIVER    SCOPE
app-overlay    overlay   swarm      <-- cluster-wide
frontend-net   bridge    local      <-- this host only
ingress        overlay   swarm
```

```console
$ docker network inspect app-overlay \
    --format 'driver={{.Driver}} scope={{.Scope}} attachable={{.Attachable}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
driver=overlay scope=swarm attachable=true subnet=10.0.1.0/24
```

`--attachable` is needed for plain `docker run` containers to join; without it only swarm *services*
can. `ingress` is created automatically for the swarm's published-port routing mesh.

### Service discovery and load balancing

```console
$ docker service create --name overlay-web --network app-overlay --replicas 3 -p 8094:80 nginx:1.27-alpine
verify: Service le3di77q21bw46wicjn2bz1ak converged

$ docker service ls
ID             NAME          MODE         REPLICAS   IMAGE               PORTS
le3di77q21bw   overlay-web   replicated   3/3        nginx:1.27-alpine   *:8094->80/tcp

$ docker service ps overlay-web --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}"
NAME            NODE             CURRENT STATE
overlay-web.1   docker-desktop   Running 11 seconds ago
overlay-web.2   docker-desktop   Running 11 seconds ago
overlay-web.3   docker-desktop   Running 11 seconds ago

$ curl -s -o /dev/null -w "status=%{http_code}\n" http://localhost:8094
status=200
```

The two DNS names a swarm service gets:

```console
$ docker run --rm --network app-overlay alpine:3.20 nslookup overlay-web
Name:	overlay-web
Address: 10.0.1.2

$ docker run --rm --network app-overlay alpine:3.20 nslookup tasks.overlay-web
Name:	tasks.overlay-web
Address: 10.0.1.4
Name:	tasks.overlay-web
Address: 10.0.1.3
Name:	tasks.overlay-web
Address: 10.0.1.5
```

- `overlay-web` → **one VIP, `10.0.1.2`**. Connections to it are load-balanced across the replicas by
  the kernel's IPVS. The VIP is not any container's address.
- `tasks.overlay-web` → **all three real task IPs**. This is the DNS round-robin form, for clients
  that want to do their own balancing.

This is the same split Kubernetes has between a **ClusterIP Service** (one stable VIP) and a
**headless Service** (all pod IPs) — which is Topic 10.

### Use cases

- Multi-host container deployments without a full Kubernetes install.
- Keeping east-west service traffic on a private virtual network while publishing only the edge.
- Legacy or smaller deployments where Swarm's simplicity beats Kubernetes' complexity.

### Honest limitation

Everything above ran on **one node** (`docker-desktop`), so the VXLAN tunnel had no peer to talk to.
I demonstrated the control plane — overlay creation, swarm scope, VIP versus task DNS, replica
scheduling — but not genuine cross-host encapsulation, which needs a second machine. The commands
and behaviour are identical; only the number of nodes differs.

### Clean up

```console
$ docker service rm overlay-web
$ docker network rm app-overlay
$ docker swarm leave --force
Node left the swarm.
$ docker rm -f web-a web-b db-only legacy-a legacy-b host-web bridge-web bind-web
$ docker network rm frontend-net backend-net
```

---

## Network driver summary

| Driver | Scope | Use it for |
|---|---|---|
| `bridge` (user-defined) | Single host | **The default choice.** Isolation + automatic DNS |
| `bridge` (default `bridge`) | Single host | Legacy. No DNS — avoid |
| `host` | Single host | Performance-critical or interface-aware workloads. No port isolation |
| `overlay` | Multi-host (swarm) | Containers spanning machines |
| `macvlan` | Single host | When a container needs its own MAC/IP on the physical LAN |
| `none` | — | Fully disable networking |
