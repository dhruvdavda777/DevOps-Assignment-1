# Session 17 – Complete CI/CD & DevSecOps

**Name:** Dhruv Davda · **Roll No:** 24BCS10203 · **Email:** Dhruv.24bcs10203@sst.scaler.com · **Group:** A

**This pipeline is real and it ran.** Workflow:
[`.github/workflows/session17-devsecops.yml`](../.github/workflows/session17-devsecops.yml) ·
Run: [#37625008502](https://github.com/dhruvdavda777/DevOps-Assignment-1/actions/runs/37625008502)

![devsecops pipeline](./screenshots/s17-01-devsecops-pipeline.png)

```
✓ SAST (Semgrep)              37s
✓ Build and unit test          5s
✓ SCA (Trivy filesystem)      24s
✓ Secret scanning (gitleaks)   5s
✓ Image build, scan and gate  1m0s
✓ Deploy to Kubernetes         6s
```

## The pipeline

```
Code ─> Build ─> Unit Test ─┐
                            ├─> SAST ────────┐
                            ├─> SCA ─────────┼─> Image Build ─> Image Scan ─> SECURITY GATE ─> Push ─> Deploy
                            └─> Secret Scan ─┘                                     │
                                                                          CRITICAL ⇒ fail,
                                                                          image never pushed
```

The four security jobs run **in parallel** with each other (they are independent), and the image job
`needs:` all of them. Fast feedback: a leaked secret fails in 5 seconds rather than after a 1-minute
image build.

| Stage | Tool | Finds |
|---|---|---|
| **SAST** | Semgrep | Vulnerable patterns in **my own code** |
| **SCA** | Trivy (fs) | Known CVEs in **dependencies** |
| **Secret scanning** | gitleaks | Credentials in code and **git history** |
| **Container scan** | Trivy (image) | CVEs in the **base image and OS packages** |
| **Gate** | `exit-code: 1` | Stops a CRITICAL image from being published |

These are four genuinely different attack surfaces. A clean SAST run says nothing about your base
image; a clean image scan says nothing about your code.

---

## 1. SAST — Semgrep

[`app/src/unsafe.js`](./app/src/unsafe.js) contains three deliberate vulnerabilities.

```console
$ docker run --rm -v $PWD/app:/src -w /src semgrep/semgrep \
    semgrep --config=p/javascript --config=p/security-audit src/unsafe.js

┌────────────────┐
│ 1 Code Finding │
└────────────────┘
    src/unsafe.js
   ❯❯❱ javascript.lang.security.detect-child-process.detect-child-process
          ❰❰ Blocking ❱❱
          Detected calls to child_process from a function argument `host`. This could lead to a
          command injection if the input is user controllable.
            8┆ exec('ping -c 1 ' + host, cb);
```

It caught the command injection and marked it **Blocking**. But it found only **one** of my three
planted bugs, so I widened the rulesets:

```console
$ semgrep --config=p/default --config=p/owasp-top-ten src/unsafe.js
│ 2 Code Findings │
   ❯❯❱ javascript.lang.security.detect-child-process.detect-child-process
            8┆ exec('ping -c 1 ' + host, cb);
           13┆ return eval(expression);
```

**Two of three.** `eval()` appeared with the broader rules; the **MD5 password hash was never
flagged by either ruleset**, even though it is a textbook weak-hashing finding.

That is the honest lesson about SAST: **coverage is entirely a function of the rules you enable, and
a clean scan is not proof of safe code.** It is a filter for known-bad patterns, not an assurance.
It also explains why SAST tools are tuned per project rather than trusted out of the box.

---

## 2. SCA — dependency CVEs

`package.json` pinned `lodash@4.17.20` specifically so the scanner had something real to find:

```console
CVE-2021-23337   HIGH   lodash 4.17.20 -> fixed in 4.17.21
    nodejs-lodash: command injection via template
CVE-2026-4800    HIGH   lodash 4.17.20 -> fixed in 4.18.0
    lodash: Arbitrary code execution via untrusted input in template imports
```

Trivy gives the installed version **and the fixed version**, which is what makes a finding
actionable rather than just alarming.

---

## 3. Secret scanning — gitleaks

**No real or realistic credential was ever committed to this repository.** The test credential is
generated at scan time into `/tmp` and never enters git history.

First attempt, using AWS's own documentation example key:

```console
$ gitleaks dir /tmp/gl-test --no-banner
INF scanned ~197 bytes (197 bytes) in 2.8ms
INF no leaks found
```

**Nothing found** — because `AKIAIOSFODNN7EXAMPLE` is the canonical AWS *documentation* key and
gitleaks allowlists it deliberately, to avoid flooding every repo that quotes AWS docs with false
positives.

With a synthetic key that does not match the allowlist:

```console
$ gitleaks dir /tmp/gl-test --no-banner -v
Finding:     aws_secret_access_key = 9ZhkDs9SAb+vVNdWZ7w899CPU6WtSYR22csssBR3
Secret:      <redacted>
RuleID:      generic-api-key
Entropy:     4.671928
File:        /tmp/gl-test/config.env
Line:        3
Fingerprint: /tmp/gl-test/config.env:generic-api-key:3

WRN leaks found: 1
```

Two useful details: it matched via the **`generic-api-key`** rule on **entropy 4.67** rather than a
specific AWS pattern, and it reports a **fingerprint** — the stable identifier used to allowlist a
reviewed false positive in `.gitleaksignore`.

In the pipeline the checkout uses `fetch-depth: 0` so **the whole history is scanned**. A secret
deleted in a later commit is still in the history and still compromised — deleting the file is not
remediation; rotating the credential is.

---

## 4. Container image scanning and the security gate

Three images, scanned identically:

```console
  dhruv/devsecops-vuln:local         HIGH/CRIT=29   OS-level=4    size=201MB
  dhruv/devsecops-hardened:local     HIGH/CRIT=13   OS-level=0    size=240MB
  dhruv/devsecops-fixed:local        HIGH/CRIT=11   OS-level=0    size=234MB
```

### The vulnerable image (`node:20.11-alpine3.18`)

```console
--- dhruv/devsecops-vuln:local (alpine 3.18.6) (alpine) ---
  CVE-2024-6119    HIGH   libcrypto3 3.1.4-r5 -> fixed in 3.1.7-r0
      openssl: Possible denial of service in X.509 name checks
  CVE-2024-6119    HIGH   libssl3 3.1.4-r5 -> fixed in 3.1.7-r0
  CVE-2025-26519   HIGH   musl 1.2.4-r2 -> fixed in 1.2.4-r3
      musl libc has an out-of-bounds write
  CVE-2025-26519   HIGH   musl-utils 1.2.4-r2 -> fixed in 1.2.4-r3

  CVE-2026-59873   CRITICAL  tar 6.2.0 -> fixed in 7.5.19
      node-tar: Denial of Service via crafted gzip bomb
```

### Remediation 1 — update the base image

Moving to `node:22-alpine` took HIGH/CRITICAL from **29 to 13** and **OS-level CVEs from 4 to zero**.
One line in the Dockerfile.

### Remediation 2 — remove the vulnerable dependency

```console
$ grep -rn 'lodash' app/src/
lodash is not imported anywhere in src/
```

**The vulnerable dependency was never used.** Removing it rather than upgrading it:

```console
TOTAL HIGH/CRITICAL: 11
  lodash findings : 0
  by package      : {'brace-expansion': 5, 'http-cache-semantics': 1, 'ip-address': 1,
                     'pacote': 2, 'picomatch': 1, 'sigstore': 1}
```

**The cheapest fix for a vulnerable dependency is often deleting it.** Unused dependencies are pure
attack surface.

### What is left, and why I did not "fix" it

All 11 remaining findings are in **npm's own bundled tooling** (`pacote`, `sigstore`,
`brace-expansion`, `picomatch`) that ships inside the official Node image — not in my application or
its dependencies. I cannot patch them from my Dockerfile. The real fixes are a distroless or
`node:22-slim` runtime that excludes npm, or waiting for an upstream image rebuild.

This is worth stating plainly because **"zero vulnerabilities" is usually not achievable**, and a
scanner that always reports findings gets ignored. That is exactly why the gate below triggers on
CRITICAL-and-fixable rather than on everything.

### The gate itself

```yaml
      - name: Build the image locally (not pushed yet)
        with:
          push: false
          load: true

      # THE SECURITY GATE: a CRITICAL finding fails the job, so the image is
      # never pushed. Scanning after pushing would be too late.
      - name: Trivy image scan (gate on CRITICAL)
        with:
          severity: CRITICAL
          exit-code: '1'          # <-- the gate
          ignore-unfixed: true

      - name: Push (only reached if the gate passed)
```

Three decisions encoded here:

1. **Build, scan, *then* push.** The image is loaded locally first. A vulnerable image never reaches
   the registry, where something could pull it.
2. **`exit-code: 1` only on CRITICAL.** HIGH is reported in a separate non-blocking step. A gate that
   blocks on everything gets disabled within a week.
3. **`ignore-unfixed: true`.** Failing a build over a CVE with no available patch gives developers no
   action to take.

---

## A pipeline failure worth recording

The first DevSecOps run **failed**, and not in the application:

```console
X main Session 17 DevSecOps · 37624835310
JOBS
X SCA (Trivy filesystem) in 2s
✓ SAST (Semgrep) in 44s
✓ Build and unit test in 9s
✓ Secret scanning (gitleaks) in 9s
- Image build, scan and gate in 0s      <-- skipped, because needs: failed

ANNOTATIONS
X Unable to resolve action `aquasecurity/trivy-action@0.28.0`, unable to find version `0.28.0`
```

I had pinned a version tag that does not exist:

```console
$ gh api repos/aquasecurity/trivy-action/releases/latest --jq '.tag_name'
v0.36.0
```

Note the `v` prefix — `0.35.0` and `v0.35.0` both exist as tags in that repository, which is exactly
the kind of inconsistency that produces this error. After pinning `v0.36.0` the full pipeline passed.

Two real lessons: **pinned action versions are a dependency like any other**, and `needs:` correctly
refused to run the image job once a prerequisite failed — the dependency graph is itself a safety
mechanism.

---

## Why each control exists

| Control | Catches | Would miss |
|---|---|---|
| Unit tests | Logic errors | Every security issue below |
| SAST | Injection, eval, unsafe APIs in **my code** | Vulnerable libraries, base image CVEs |
| SCA | Known CVEs in **declared dependencies** | My own code, OS packages |
| Secret scanning | Credentials in code **and history** | Secrets in a running environment |
| Image scanning | **OS package** CVEs, transitive deps | Logic errors, misconfiguration |
| Security gate | Turns findings into **enforcement** | Anything the scanners above miss |

Without the gate, all of this is a report nobody reads. The gate is what makes it DevSec**Ops**.

## What I understood

- **Shift left, but measure.** The cheap fast checks (secrets, 5s) run before the expensive ones
  (image build + scan, 1m).
- **Scan before publishing.** Build locally, scan, then push — the ordering is the control.
- **Tune the gate or lose it.** Blocking only on CRITICAL + fixable keeps the signal credible.
- **A clean SAST run proves very little** — it missed my MD5 hash entirely, with two rulesets.
- **Deleting an unused dependency beats upgrading it**, and is often the fastest remediation.
- **Scanner allowlists are a real phenomenon** — gitleaks silently ignored AWS's documentation key,
  which would be very confusing when testing a pipeline for the first time.
- **You will not reach zero findings**, and a policy that demands it will be switched off.
