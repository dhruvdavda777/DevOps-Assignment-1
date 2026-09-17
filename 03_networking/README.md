# Topic 03 – Networking

**Name:** Dhruv Davda
**Roll No:** 24BCS10203
**Email:** Dhruv.24bcs10203@sst.scaler.com
**Group:** A

All commands were run on my own machine (macOS on Apple Silicon) against my campus network. My
hardware MAC address is masked in the output below; everything else is unedited.

## Command summary

| Command | One line purpose |
|---|---|
| `ifconfig` / `ip a` | What is my IP address, netmask and interface state |
| `ping` | Is the host reachable, and how long does a round trip take |
| `traceroute` | Which routers does my packet pass through |
| `netstat -rn` / `netstat -an` | Routing table / sockets and listening ports |
| `nslookup`, `dig`, `host` | Resolve a name to an address, query any record type |
| `curl` | Speak HTTP: status codes, headers, redirects, timing |
| `nc` | Is a single TCP port open, closed or filtered |

---

## 1. `ifconfig` – my own address

```console
$ ifconfig en0 | head -8
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	options=6460<TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>
	ether xx:xx:xx:xx:xx:xx
	inet6 fe80::1839:1a40:32f8:1f8f%en0 prefixlen 64 secured scopeid 0xf
	inet 172.20.1.251 netmask 0xfffff800 broadcast 172.20.7.255
	nd6 options=201<PERFORMNUD,DAD>
	media: autoselect
	status: active

$ ipconfig getifaddr en0
172.20.1.251
```

Reading this line by line:

- `en0` is my Wi-Fi interface. `UP` and `RUNNING` mean the interface is enabled *and* has a carrier.
- `mtu 1500` is the largest payload one Ethernet frame can carry.
- `ether xx:xx:...` is the layer-2 MAC address, `inet 172.20.1.251` is the layer-3 IPv4 address.
- `netmask 0xfffff800` is hex for `255.255.248.0`, which is a **/21**. So my network is
  `172.20.0.0/21`, usable hosts `172.20.0.1`–`172.20.7.254`, and the broadcast address is
  `172.20.7.255` — which matches what `ifconfig` reports.
- `fe80::` is a link-local IPv6 address, generated automatically and never routable off the link.

`172.20.x.x` is in the private range `172.16.0.0/12`, so this is an internal campus address behind
NAT, not something reachable from the internet.

---

## 2. `ping` – reachability and latency

```console
$ ping -c 4 google.com
PING google.com (142.251.43.46): 56 data bytes
64 bytes from 142.251.43.46: icmp_seq=0 ttl=118 time=12.784 ms
64 bytes from 142.251.43.46: icmp_seq=1 ttl=118 time=21.904 ms
64 bytes from 142.251.43.46: icmp_seq=2 ttl=118 time=12.558 ms
64 bytes from 142.251.43.46: icmp_seq=3 ttl=118 time=12.186 ms

--- google.com ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 12.186/14.858/21.904/4.074 ms

$ ping -c 3 127.0.0.1
64 bytes from 127.0.0.1: icmp_seq=2 ttl=64 time=0.068 ms

--- 127.0.0.1 ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 0.068/0.112/0.141/0.031 ms
```

What the numbers mean:

- `0.0% packet loss` is the headline. Loss matters more than latency: 200 ms with no loss is a slow
  but working link, 20 ms with 30% loss is a broken one.
- `icmp_seq` increments per packet, so a gap in the sequence is a dropped packet.
- `ttl=118` on the reply is the remaining Time To Live. Linux and Android start at 64, Windows at
  128. A reply arriving with 118 suggests the sender started at 128 and the packet crossed about
  **10 routers**.
- Loopback is ~0.07 ms versus ~13 ms to Google — three orders of magnitude, because `127.0.0.1`
  never leaves the kernel and no physical medium is involved.
- `ping` uses **ICMP, not TCP**. A host that does not answer ping is not necessarily down; many
  firewalls drop ICMP while happily serving HTTP. That is precisely why `nc` in section 7 exists.

---

## 3. `traceroute` – the path a packet takes

```console
$ traceroute -m 12 -q 1 google.com
traceroute to google.com (142.251.43.46), 12 hops max, 40 byte packets
 1  172.20.0.1 (172.20.0.1)  13.969 ms
 2  49.200.242.17 (49.200.242.17)  12.355 ms
 3  128.185.120.53 (128.185.120.53)  8.104 ms
 4  182.79.142.222 (182.79.142.222)  15.941 ms
 5  *
 6  142.251.70.211 (142.251.70.211)  24.561 ms
 7  209.85.247.250 (209.85.247.250)  14.317 ms
 8  142.251.55.227 (142.251.55.227)  13.645 ms
 9  142.251.230.71 (142.251.230.71)  21.848 ms
10  142.251.55.227 (142.251.55.227)  22.933 ms
11  bkk02s01-in-f14.1e100.net (142.251.43.46)  13.535 ms
```

- **Hop 1, `172.20.0.1`, is my default gateway** — the same address `netstat -rn` lists as
  `default` in the next section. Every packet leaving my laptop starts there.
- Hops 2–4 are my ISP's network; from hop 6 onward the addresses belong to Google (`142.251.x.x`),
  and the final hop resolves to `1e100.net`, which is Google's PTR domain (1e100 = 10^100 = a googol).
- **Hop 5 is `*`** — that router did not send back an ICMP Time Exceeded message. This is normal:
  many routers are configured not to reply, or rate-limit ICMP. A single `*` in the middle with
  traffic still reaching the destination is not a fault.
- Hop 8 and hop 10 show the **same address, `142.251.55.227`**. Inside a large provider, load
  balancing means consecutive probes can take different physical paths, so the list is not always a
  strictly increasing walk. It shows why traceroute is a hint, not a map.
- How it works: traceroute sends packets with TTL=1, 2, 3, … Each router that decrements the TTL to
  zero returns *ICMP Time Exceeded*, which reveals its address.

---

## 4. `netstat` – routing table and open ports

```console
$ netstat -rn | head -8
Routing tables

Internet:
Destination        Gateway            Flags               Netif Expire
default            172.20.0.1         UGScg                 en0
127                127.0.0.1          UCS                   lo0
127.0.0.1          127.0.0.1          UH                    lo0
169.254            link#15            UCS                   en0      !
```

- The `default` route is the fallback for any destination with no more specific entry — my gateway
  `172.20.0.1`. Flags `U`=up, `G`=gateway, `S`=static.
- `127/8` goes to `lo0`, the loopback interface.
- `169.254/16` is the link-local range used when DHCP fails; seeing traffic there usually means "I
  never got an address".
- The kernel always picks the **most specific matching prefix**, and only falls back to `default`.

```console
$ netstat -an | grep LISTEN | head -8
tcp4       0      0  127.0.0.1.54929        *.*                    LISTEN
tcp4       0      0  *.443                  *.*                    LISTEN
tcp4       0      0  *.80                   *.*                    LISTEN
tcp4       0      0  127.0.0.1.56708        *.*                    LISTEN
tcp46      0      0  *.5433                 *.*                    LISTEN
tcp4       0      0  127.0.0.1.55334        *.*                    LISTEN
tcp46      0      0  *.3000                 *.*                    LISTEN
tcp4       0      0  127.0.0.1.20275        *.*                    LISTEN
```

The important distinction here is the bind address:

- `127.0.0.1.54929` is bound to **loopback only** — reachable from this machine and nothing else.
  This one is the `kube-apiserver` of my kind cluster (confirmed in section 7).
- `*.80` and `*.443` are bound to **all interfaces**, so other machines on the campus network could
  connect. These two are the host port mappings my kind cluster publishes for the ingress
  controller used in Topic 11.
- `tcp46` means the socket accepts both IPv4 and IPv6.

On Linux `netstat` is deprecated in favour of `ss -tulpn`, and `ip a` / `ip r` replace `ifconfig` /
`netstat -rn`. I used the BSD tools here because that is what macOS ships.

---

## 5. `nslookup`, `dig` and `host` – DNS

```console
$ nslookup scaler.com
Server:		1.1.1.1
Address:	1.1.1.1#53

Non-authoritative answer:
Name:	scaler.com
Address: 108.159.28.116
Name:	scaler.com
Address: 108.159.28.90
Name:	scaler.com
Address: 108.159.28.105
Name:	scaler.com
Address: 108.159.28.79
```

- My resolver is **Cloudflare, `1.1.1.1`, on port 53**.
- **Non-authoritative** means the answer came from the resolver's cache, not from the domain's own
  authoritative nameserver.
- Four A records for one name is DNS-level load balancing; the client picks one.

```console
$ dig +short github.com
20.207.73.82

$ dig github.com A +noall +answer
; <<>> DiG 9.10.6 <<>> github.com A +noall +answer
;; global options: +cmd
github.com.		22	IN	A	20.207.73.82

$ dig scaler.com MX +short
1 aspmx.l.google.com.
10 aspmx2.googlemail.com.
10 aspmx3.googlemail.com.
5 alt1.aspmx.l.google.com.
5 alt2.aspmx.l.google.com.
```

- `dig +short` is the version to use inside scripts — one address, nothing to parse around.
- In the full answer, `22` is the **TTL in seconds**: how much longer a resolver may cache this
  record. `IN` is the class (Internet) and `A` the record type.
- The `MX` numbers are **priorities, lowest first**. Mail for `scaler.com` goes to
  `aspmx.l.google.com` (1) and only falls back to the priority 10 hosts if that fails.

### Something I did not expect

```console
$ host sst.scaler.com
sst.scaler.com mail is handled by 1 smtp.google.com.

$ dig sst.scaler.com A +short
(no output)

$ dig sst.scaler.com MX +short
1 smtp.google.com.
```

My own college domain, the one in my email address, has an **MX record but no A record**. So
`sst.scaler.com` can receive mail but there is no web server behind that exact hostname. This also
explains the `curl` result in the next section, and it is a good reminder that "the DNS name exists"
and "there is a website there" are two different questions.

---

## 6. `curl` – testing HTTP

```console
$ curl -sI https://github.com
HTTP/2 200
date: Thu, 17 Sep 2026 15:09:06 GMT
content-type: text/html; charset=utf-8
content-language: en-US
vary: X-PJAX, X-PJAX-Container, Turbo-Visit, Turbo-Frame, ...
etag: W/"e3fb91a5ed30f8c795d2554e1b7f38bc"
cache-control: max-age=0, private, must-revalidate
strict-transport-security: max-age=31536000; includeSubdomains; preload
```

- `-I` sends a `HEAD` request: headers only, no body. Ideal for a quick health check.
- `HTTP/2 200` — the protocol negotiated over TLS ALPN was HTTP/2, and the status is OK.
- `strict-transport-security` tells the browser to refuse plain HTTP to this host in future.

Following a redirect, and measuring where the time goes:

```console
$ curl -sL -o /dev/null -w "%{http_code} -> %{url_effective}\n" http://github.com
200 -> https://github.com/

$ curl -s https://api.github.com/zen
Mind your words, they are important.

$ curl -s -o /dev/null -w "code=%{http_code} dns=%{time_namelookup}s connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s\n" https://sst.scaler.com
code=000 dns=0.000000s connect=0.000000s tls=0.000000s total=0.018587s
```

- `-L` follows redirects; `%{url_effective}` proves the plain-HTTP request ended up on HTTPS.
- `-w` with `%{time_namelookup}` / `%{time_connect}` / `%{time_appconnect}` splits a slow request
  into DNS vs TCP vs TLS, which is how you tell *why* something is slow rather than just *that* it is.
- The last command is a failure, and the numbers say exactly why: **`code=000` with
  `dns=0.000000s`**. Status `000` means no HTTP response was ever received, and a DNS time of zero
  means it never even got an address — consistent with the missing A record found in section 5. Had
  DNS succeeded and the server been down, I would instead see a non-zero `time_namelookup` and a
  connect failure.

Flags worth remembering: `-s` silent, `-i` include headers with the body, `-v` full handshake,
`-o file` save output, `-X POST -d '{...}' -H 'Content-Type: application/json'` to send JSON,
`-f` to make curl exit non-zero on a 4xx/5xx (essential in CI scripts).

---

## 7. `nc` (netcat) – is a TCP port open?

```console
$ nc -zv github.com 443
Connection to github.com port 443 [tcp/https] succeeded!

$ nc -zv 127.0.0.1 54929      # kube-apiserver of my kind cluster
Connection to 127.0.0.1 port 54929 [tcp/*] succeeded!

$ nc -zv -w 3 127.0.0.1 9099  # nothing listening here
nc: connectx to 127.0.0.1 port 9099 (tcp) failed: Connection refused

$ nc -zv -w 5 github.com 23   # telnet, blocked upstream
nc: connectx to github.com port 23 (tcp) failed: Operation timed out
```

`-z` scans without sending data, `-v` prints the result, `-w` sets a timeout.

**The three outcomes are diagnostically different, and this is the main thing I took from this
topic:**

| Result | What happened | What it means |
|---|---|---|
| `succeeded!` | TCP handshake completed | Something is listening and reachable |
| `Connection refused` | The host replied with TCP RST | Host is up, **nothing is bound** to that port |
| `Operation timed out` | No reply at all | A **firewall is silently dropping** the packets |

"Refused" is a fast, definite answer from a reachable machine. "Timed out" is silence, and silence
is what a firewall produces. Confusing the two wastes a lot of debugging time.

The kind API server port (`54929`) also confirms the loopback binding seen in `netstat`: the port is
random per cluster and published only on `127.0.0.1`, which is why I had to look it up with
`docker port dhruv-devops-control-plane 6443/tcp` rather than assume the usual `6443`.

---

## IP addressing notes

| Range | Purpose |
|---|---|
| `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | Private (RFC 1918), not routable on the internet |
| `127.0.0.0/8` | Loopback, never leaves the host |
| `169.254.0.0/16` | Link-local, self-assigned when DHCP fails |
| `224.0.0.0/4` | Multicast |

A prefix length is just the count of leading `1` bits in the mask, and it fixes the size of the
network:

| CIDR | Mask | Usable hosts |
|---|---|---|
| /24 | 255.255.255.0 | 254 |
| /21 | 255.255.248.0 | 2046 ← my campus network |
| /16 | 255.255.0.0 | 65534 |

Two addresses in every subnet are reserved — the network address (all host bits `0`) and the
broadcast address (all host bits `1`) — which is where the "minus 2" comes from.

Ports: 0–1023 are well-known and need root to bind (22 SSH, 53 DNS, 80 HTTP, 443 HTTPS),
1024–49151 are registered (3000, 5432, 6443, 8080), and 49152–65535 are ephemeral — which is the
range kind picked `54929` from.

---

## The order I would troubleshoot in

Bottom of the stack upward, so that each step only tests one new thing:

1. **Do I have an address?** `ifconfig en0` / `ip a`. A `169.254.x.x` address means DHCP failed.
2. **Can I reach my gateway?** `ping 172.20.0.1`. Fails → the problem is on my own LAN.
3. **Can I reach the internet by IP?** `ping 1.1.1.1`. This deliberately skips DNS.
4. **Does DNS work?** `dig example.com`. If step 3 passed but this fails, it is purely a resolver
   problem — the classic "internet is down" that is actually DNS.
5. **Is the port open?** `nc -zv host 443`. Distinguish refused (nothing listening) from timed out
   (firewall).
6. **Is the application healthy?** `curl -I https://host`, then `-w` timings to see whether DNS, TCP,
   TLS or the server itself is the slow part.
7. **Where does the path break?** `traceroute host`, for anything that looks like a routing problem.

Each step assumes the one before it succeeded, which is what makes the sequence useful: the first
command that fails tells you which layer to actually investigate.
