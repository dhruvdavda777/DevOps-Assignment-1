# Topic 02 – Shell Scripting

**Name:** Dhruv Davda
**Roll No:** 24BCS10203
**Email:** Dhruv.24bcs10203@sst.scaler.com
**Group:** A

## Task

Write a shell script that reports information about the system it runs on, and that also creates a
directory and a file of its own so that the script has a side effect on disk, not only on screen.

My script is [`sysinfo.sh`](./sysinfo.sh). It prints a sectioned report (host, OS, uptime, CPU,
memory, disk, heaviest processes) and then writes a full `ps -ef` snapshot into
`system_info/process.log`, creating the `system_info/` directory if it does not exist.

It was run inside an `ubuntu:24.04` container, since my host is macOS and the script reads Linux
specific paths such as `/proc/cpuinfo`:

```bash
docker run --rm -v "$PWD":/work -w /work ubuntu:24.04 bash
```

## The script

```bash
#!/bin/bash
#
# sysinfo.sh - collects basic information about the machine it runs on.
#
# Author : Dhruv Davda (24BCS10203)
# Course : DevOps - Assignment 1, Shell Scripting

set -u

REPORT_DIR="system_info"
PROCESS_LOG="$REPORT_DIR/process.log"

# --- a small helper so every section is printed the same way -------------
section() {
    echo ""
    echo "===================================================="
    echo " $1"
    echo "===================================================="
}

section "HOST"
echo "Hostname      : $(hostname)"
echo "Kernel        : $(uname -s) $(uname -r)"
echo "Architecture  : $(uname -m)"
echo "Current user  : $(whoami)"
echo "Date and time : $(date '+%Y-%m-%d %H:%M:%S')"

section "OPERATING SYSTEM"
if [ -f /etc/os-release ]; then
    grep 'PRETTY_NAME' /etc/os-release | cut -d '"' -f 2
else
    echo "/etc/os-release not found on this system"
fi

section "UPTIME AND LOAD"
uptime

section "CPU"
if [ -f /proc/cpuinfo ]; then
    echo "Cores         : $(grep -c '^processor' /proc/cpuinfo)"
    # x86 exposes "model name", ARM exposes "Model" or only the implementer id,
    # so fall back through the options instead of printing an empty line.
    CPU_MODEL=$(grep -m 1 -E '^(model name|Model)[[:space:]]*:' /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^ //')
    if [ -z "$CPU_MODEL" ]; then
        CPU_MODEL=$(grep -m 1 'CPU implementer' /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^ //')
        [ -n "$CPU_MODEL" ] && CPU_MODEL="ARM implementer $CPU_MODEL ($(uname -m))"
    fi
    echo "Model         : ${CPU_MODEL:-not reported by this kernel}"
else
    echo "Cores         : $(nproc 2>/dev/null || echo unknown)"
    echo "Model         : $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
fi

section "MEMORY"
free -h 2>/dev/null || echo "free is not available on this system"

section "DISK USAGE"
df -h / 2>/dev/null

section "TOP 5 PROCESSES BY MEMORY"
# --sort=-%mem puts the heaviest process first, head -6 keeps the header row
ps -eo pid,user,%cpu,%mem,comm --sort=-%mem 2>/dev/null | head -6

# --- store a full process snapshot on disk -------------------------------
if [ ! -d "$REPORT_DIR" ]; then
    mkdir -p "$REPORT_DIR"
    echo ""
    echo "Created directory: $REPORT_DIR"
fi

{
    echo "Process snapshot taken on $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Host: $(hostname)"
    echo ""
    ps -ef
} > "$PROCESS_LOG"

echo "Saved process list to: $PROCESS_LOG ($(wc -l < "$PROCESS_LOG") lines)"
echo ""
echo "Report finished."
```

## How to run it

```bash
chmod +x sysinfo.sh
./sysinfo.sh
```

## Output

```console
$ chmod +x sysinfo.sh
$ ./sysinfo.sh

====================================================
 HOST
====================================================
Hostname      : 0c94443ea411
Kernel        : Linux 6.12.76-linuxkit
Architecture  : aarch64
Current user  : root
Date and time : 2026-09-17 15:05:10

====================================================
 OPERATING SYSTEM
====================================================
Ubuntu 24.04.5 LTS

====================================================
 UPTIME AND LOAD
====================================================
 15:05:10 up  7:50,  0 user,  load average: 0.32, 0.30, 0.30

====================================================
 CPU
====================================================
Cores         : 15
Model         : ARM implementer 0x61 (aarch64)

====================================================
 MEMORY
====================================================
               total        used        free      shared  buff/cache   available
Mem:           7.7Gi       1.4Gi       169Mi        21Mi       6.4Gi       6.4Gi
Swap:          1.0Gi          0B       1.0Gi

====================================================
 DISK USAGE
====================================================
Filesystem      Size  Used Avail Use% Mounted on
overlay         911G   62G  803G   8% /

====================================================
 TOP 5 PROCESSES BY MEMORY
====================================================
  PID USER     %CPU %MEM COMMAND
  159 root      0.0  0.0 ps
  137 root      0.0  0.0 sysinfo.sh
    1 root      0.1  0.0 bash
  160 root      0.0  0.0 head

Created directory: system_info
Saved process list to: system_info/process.log (7 lines)

Report finished.
```

### The directory and file the script created

```console
$ ls -R system_info
system_info:
process.log

$ head -6 system_info/process.log
Process snapshot taken on 2026-09-17 15:05:10
Host: 0c94443ea411

UID        PID  PPID  C STIME TTY          TIME CMD
root         1     0  0 15:05 ?        00:00:00 bash -c ...
root       137     1  0 15:05 ?        00:00:00 /bin/bash ./sysinfo.sh
```

## Things that went wrong, and what I changed

**The CPU model printed as an empty string on the first run.** My original line was

```bash
echo "Model         : $(grep -m 1 'model name' /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^ //')"
```

which works on x86 but produced `Model         :` with nothing after it. The reason is that
`model name` is an **x86-only field**. My Mac is Apple Silicon, so the container runs on an
`aarch64` kernel whose `/proc/cpuinfo` exposes `CPU implementer` / `CPU part` instead. I rewrote the
block to try `model name`, then `Model`, then `CPU implementer`, and to fall back to a clear
`not reported by this kernel` message — which is why the output above reads
`ARM implementer 0x61 (aarch64)` (`0x61` is Apple).

I also added a macOS branch using `sysctl -n machdep.cpu.brand_string`, so the same script gives a
sensible answer if it is run on the host instead of in the container.

## What I understood

- `#!/bin/bash` is the **shebang**. It tells the kernel which interpreter to hand the file to, which
  is why `./sysinfo.sh` works once the file is executable. Without `chmod +x` the kernel refuses
  with `Permission denied`, even though `bash sysinfo.sh` would still work.
- **Command substitution** `$(...)` runs a command and substitutes its standard output. Nesting it
  inside a quoted string, as in `"Cores : $(grep -c ...)"`, is what lets me build aligned output
  without `printf` gymnastics.
- `set -u` makes the script exit if I use a variable I never assigned. It caught a typo'd variable
  name while I was writing this, which is exactly the point. `set -e` (exit on error) was
  deliberately **not** used here, because I *want* the script to keep going and print a fallback
  message when an optional command like `free` is missing.
- Defining `section()` as a function removed six copies of the same three `echo` lines. Functions in
  bash take no parameter list — arguments simply arrive as `$1`, `$2`, and so on.
- **Grouping with braces and redirecting once** is much better than appending line by line:
  ```bash
  { echo header; ps -ef; } > "$PROCESS_LOG"
  ```
  This opens the file a single time. Using `>>` on each line would reopen it repeatedly, and a stray
  `>` instead of `>>` would silently truncate everything written before it.
- `[ ! -d "$REPORT_DIR" ]` plus `mkdir -p` makes the script **idempotent** — running it twice does
  not fail and does not print a misleading "Created directory" message the second time.
- Quoting `"$PROCESS_LOG"` everywhere is not decoration. If the path ever contains a space, an
  unquoted variable would split into two arguments and the redirect would fail.
- `ps -eo pid,user,%cpu,%mem,comm --sort=-%mem` is the portable way to answer "what is eating my
  memory" in a script. Parsing the output of `top` would be far more fragile since `top` is built
  for interactive use.
- A practical container lesson: `ps` and `free` come from the **`procps`** package, which is not in
  the slim `ubuntu:24.04` image. I had to `apt-get install -y procps` before the script could
  complete. A script is only as portable as the binaries it assumes exist.
