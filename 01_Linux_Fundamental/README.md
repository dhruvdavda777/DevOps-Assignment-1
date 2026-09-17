# Topic 01 – Linux Fundamentals

**Name:** Dhruv Davda
**Roll No:** 24BCS10203
**Email:** Dhruv.24bcs10203@sst.scaler.com
**Group:** A

My laptop is macOS on Apple Silicon, so every Linux command below was run inside a real Linux
environment on that machine:

- **Tasks 1 and 2** – an `ubuntu:24.04` container (`docker run --rm -it ubuntu:24.04 bash`).
- **Task 3** – the control-plane node of my `kind` cluster, because a plain Ubuntu container has no
  PID 1 `systemd` and therefore no journal. The kind node image *does* boot systemd, so
  `journalctl` behaves exactly like it does on a normal Linux server.

Every block marked `$` is copied from my terminal.

---

## Task 1: Soft link vs hard link

### The difference

|  | Hard link | Soft (symbolic) link |
|---|---|---|
| What it points at | The **inode** – the data itself | The **pathname** of another file |
| How to create | `ln target name` | `ln -s target name` |
| Does it get its own inode? | No, it reuses the target's inode | Yes, it is a tiny separate file |
| Link count of the target | Goes up by one | Unchanged |
| Size | Same as the file | Number of characters in the stored path |
| If the target is removed | Data still reachable through the link | Link dangles, reads fail with `ENOENT` |
| Can it cross filesystems? | No, inodes are per filesystem | Yes |
| Can it point at a directory? | No (only root may, and it is forbidden in practice) | Yes |
| `ls -l` first character | `-`, looks like an ordinary file | `l`, and shows `name -> target` |

### Practice

```console
$ echo "notes for devops assignment" > source.txt
$ ln source.txt hard_copy.txt
$ ln -s source.txt soft_copy.txt

$ ls -li
total 8
1159385 -rw-r--r-- 2 root root 28 Sep 17 15:02 hard_copy.txt
1159386 lrwxrwxrwx 1 root root 10 Sep 17 15:02 soft_copy.txt -> source.txt
1159385 -rw-r--r-- 2 root root 28 Sep 17 15:02 source.txt

$ stat -c "%n inode=%i links=%h type=%F size=%s" source.txt hard_copy.txt soft_copy.txt
source.txt inode=1159385 links=2 type=regular file size=28
hard_copy.txt inode=1159385 links=2 type=regular file size=28
soft_copy.txt inode=1159386 links=1 type=symbolic link size=10
```

Writing through the hard link, then reading through the original name:

```console
$ echo "line added through the hard link" >> hard_copy.txt
$ cat source.txt
notes for devops assignment
line added through the hard link
```

Now deleting the original file, which is the interesting part:

```console
$ rm source.txt
$ ls -li
total 4
1159385 -rw-r--r-- 1 root root 61 Sep 17 15:02 hard_copy.txt
1159386 lrwxrwxrwx 1 root root 10 Sep 17 15:02 soft_copy.txt -> source.txt

$ cat hard_copy.txt
notes for devops assignment
line added through the hard link

$ cat soft_copy.txt
cat: soft_copy.txt: No such file or directory

$ readlink soft_copy.txt
source.txt
```

### What I understood

- `source.txt` and `hard_copy.txt` printed the **same inode number, 1159385**, and a link count of
  `2`. They were never two files — they are two directory entries naming one inode.
- `soft_copy.txt` got its **own inode (1159386)** and a size of exactly **10 bytes**, which is the
  length of the string `source.txt`. A symlink literally stores a path as its contents.
- Appending through `hard_copy.txt` changed what `cat source.txt` printed, because there is only one
  copy of the data on disk.
- After `rm source.txt` the link count on the inode dropped from `2` to `1` and the file was still
  perfectly readable. `rm` removes a *name*, and the kernel only frees the data when the link count
  reaches `0` and no process holds the file open.
- The symlink survived as a file but broke as a link — `readlink` still happily reports its target
  `source.txt`, even though resolving that path now fails. This is why a dangling symlink shows up
  in `ls` but errors on `cat`.

**One-line answer:** a hard link is a second name for the same inode; a soft link is a separate file
whose content is a path to another file.

---

## Task 2: `adduser` vs `useradd`

### The difference

|  | `useradd` | `adduser` |
|---|---|---|
| What it is | The low level binary from `shadow-utils`, present on every distro | A Perl/shell wrapper on Debian and Ubuntu that calls `useradd` for you |
| Home directory | Not created unless you pass `-m` | Created automatically |
| Default shell | `/bin/sh` | `/bin/bash` |
| `/etc/skel` dotfiles | Only copied with `-m` | Always copied |
| Supplementary groups | None | Adds the user to sensible defaults such as `users` |
| Password / full name | A separate `passwd` call | Prompted for interactively |
| Behaviour | Silent, exit status only | Prints every step it performs |
| Best suited to | Scripts and Dockerfiles, portable across distros | Creating an account by hand on Ubuntu/Debian |

**On Ubuntu I would use `adduser`** for interactive work, because a single command produces a
genuinely usable account. In a Dockerfile or provisioning script I would use `useradd`, because it
is non-interactive by nature and exists on RHEL, Alpine and Ubuntu alike.

A detail worth recording: `adduser` was **not present** in the slim `ubuntu:24.04` image, so I had
to `apt-get install -y adduser` first. `useradd` was already there. That alone shows which of the
two is the primitive.

### Practice

```console
# adduser installed from the ubuntu archive (not present in the slim base image)

$ useradd dhruv_low
$ grep dhruv_low /etc/passwd
dhruv_low:x:1001:1001::/home/dhruv_low:/bin/sh
$ ls -A /home/dhruv_low
ls: cannot access '/home/dhruv_low': No such file or directory

$ adduser --disabled-password --gecos "" dhruv_high
info: Adding user `dhruv_high' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `dhruv_high' (1002) ...
info: Adding new user `dhruv_high' (1002) with group `dhruv_high (1002)' ...
info: Creating home directory `/home/dhruv_high' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `dhruv_high' to supplemental / extra groups `users' ...
info: Adding user `dhruv_high' to group `users' ...

$ grep dhruv_high /etc/passwd
dhruv_high:x:1002:1002:,,,:/home/dhruv_high:/bin/bash
$ ls -A /home/dhruv_high
.bash_logout
.bashrc
.profile
$ ls -A /etc/skel
.bash_logout
.bashrc
.profile

$ id dhruv_low && id dhruv_high
uid=1001(dhruv_low) gid=1001(dhruv_low) groups=1001(dhruv_low)
uid=1002(dhruv_high) gid=1002(dhruv_high) groups=1002(dhruv_high),100(users)
```

`--disabled-password --gecos ""` were passed only so the command does not stop to ask me questions
inside a non-interactive container.

Making `useradd` produce the same result needs three extra flags:

```console
$ useradd -m -s /bin/bash dhruv_fixed
$ grep dhruv_fixed /etc/passwd; ls -A /home/dhruv_fixed
dhruv_fixed:x:1002:1002::/home/dhruv_fixed:/bin/bash
.bash_logout
.bashrc
.profile
```

### Deleting the users

```console
$ apt-get install -y perl        # required by deluser --remove-home
$ deluser --remove-home dhruv_high
info: Looking for files to backup/remove ...
info: Removing files ...
warn: `/usr/bin/crontab' not executed. Skipping crontab removal. Package `cron' required.
info: Removing user `dhruv_high' ...
$ ls -A /home
ubuntu

$ userdel -r dhruv_low
userdel: dhruv_low mail spool (/var/mail/dhruv_low) not found
userdel: dhruv_low home directory (/home/dhruv_low) not found
```

### What I understood

- The two accounts differed in exactly the ways the table predicts: `dhruv_low` got `/bin/sh`, **no
  home directory at all** and only its own group; `dhruv_high` got `/bin/bash`, a populated home
  directory and the extra `users` group.
- `/etc/skel` is the template. The three dotfiles in `/home/dhruv_high` are byte-for-byte the three
  files in `/etc/skel` — `adduser` simply copies that directory.
- `userdel -r dhruv_low` warned that there was no home directory and no mail spool to remove. Those
  are warnings, not failures: the account row in `/etc/passwd` was still deleted. It is a neat
  confirmation that `useradd` without `-m` never created a home directory in the first place.
- `deluser --remove-home` refused to run until I installed `perl`, which is the clearest possible
  evidence that `deluser`/`adduser` are Perl scripts layered on top of the C binaries.

---

## Task 3: `journalctl`

`journalctl` reads the binary log database maintained by `systemd-journald`. Unlike plain text files
in `/var/log`, the journal is indexed and structured, so it can be filtered by unit, priority, boot
and time without `grep`.

### Commands I practised

```console
$ systemctl is-system-running
running

$ journalctl --no-pager -n 5
Sep 17 15:06:13 dhruv-devops-control-plane kubelet[764]: I0917 15:06:13.293275     764 pod_startup_latency_tracker.go:144] "Observed pod startup duration" pod="kube-system/coredns-559f6c778d-d96kk" podStartSLOduration=12.293259554 ...
Sep 17 15:06:13 dhruv-devops-control-plane kubelet[764]: I0917 15:06:13.417738     764 server.go:177] "Pod update broadcasted" podUID="690b1156-f874-4b6d-ab61-13f89dc730d3" type="MODIFIED"
Sep 17 15:06:13 dhruv-devops-control-plane kubelet[764]: I0917 15:06:13.417799     764 server.go:177] "Pod update broadcasted" podUID="66d9ea05-eb44-4227-8511-0647f286363d" type="MODIFIED"
Sep 17 15:06:14 dhruv-devops-control-plane kubelet[764]: I0917 15:06:14.419524     764 server.go:177] "Pod update broadcasted" podUID="690b1156-f874-4b6d-ab61-13f89dc730d3" type="MODIFIED"
Sep 17 15:06:14 dhruv-devops-control-plane kubelet[764]: I0917 15:06:14.419683     764 server.go:177] "Pod update broadcasted" podUID="66d9ea05-eb44-4227-8511-0647f286363d" type="MODIFIED"
```

Filtering by unit — only the kubelet's own messages:

```console
$ journalctl -u kubelet --no-pager -n 6
Sep 17 15:06:13 dhruv-devops-control-plane kubelet[764]: I0917 15:06:13.285932     764 pod_startup_latency_tracker.go:144] "Observed pod startup duration" pod="kube-system/coredns-559f6c778d-544bf" ...
Sep 17 15:06:13 dhruv-devops-control-plane kubelet[764]: I0917 15:06:13.417738     764 server.go:177] "Pod update broadcasted" podUID="690b1156-f874-4b6d-ab61-13f89dc730d3" type="MODIFIED"
...
```

Filtering by priority, by time, and choosing a different output format:

```console
$ journalctl -p err --no-pager -n 5
-- No entries --

$ journalctl --since "10 minutes ago" --no-pager | wc -l
864

$ journalctl --disk-usage
Archived and active journals take up 8M in the file system.

$ journalctl -u containerd --no-pager -n 3 -o short-iso
2026-09-17T15:06:13+00:00 dhruv-devops-control-plane containerd[129]: time="2026-09-17T15:06:13.243755387Z" level=info msg="StartContainer for \"0ddc6f50ad84996936ca9118b036e7e2d9f8fed71f13243475770e6c873a0d95\" returns successfully"
2026-09-17T15:06:13+00:00 dhruv-devops-control-plane containerd[129]: time="2026-09-17T15:06:13.271661096Z" level=info msg="StartContainer for \"d180e3dc1a0edb9e562447bce2b3eb24ca387911438b6c793b83c8c29bad6725\" returns successfully"
2026-09-17T15:06:13+00:00 dhruv-devops-control-plane containerd[129]: time="2026-09-17T15:06:13.281673804Z" level=info msg="StartContainer for \"ae142f873d959a2e1bc490dff029350a7d04829df6d4baf36b3ea2e8e3f66b8e\" returns successfully"

$ systemctl list-units --type=service --state=running --no-pager | head -4
  UNIT                     LOAD   ACTIVE SUB     DESCRIPTION
  containerd.service       loaded active running containerd container runtime
  kubelet.service          loaded active running kubelet: The Kubernetes Node Agent
  systemd-journald.service loaded active running Journal Service
```

### Flags I will actually remember

| Command | What it gives me |
|---|---|
| `journalctl -u <unit>` | Logs of one service only |
| `journalctl -f` | Live tail, like `tail -f` |
| `journalctl -n 50` | Last 50 lines |
| `journalctl -p err` | Priority `err` and worse (`emerg alert crit err warning notice info debug`) |
| `journalctl -b` / `-b -1` | This boot / the previous boot |
| `journalctl --since "10 min ago" --until "now"` | Time window, accepts plain English |
| `journalctl -o json-pretty` | Full structured fields, not just the message |
| `journalctl --disk-usage` | How much space the journal occupies |
| `journalctl --vacuum-time=2d` | Delete journal data older than two days |
| `journalctl -k` | Kernel ring buffer, the `dmesg` equivalent |

### What I understood

- The journal is **structured, not text**. Each entry carries fields such as `_SYSTEMD_UNIT`,
  `_PID` and `PRIORITY`, which is why `-u kubelet` can filter exactly instead of grepping for a
  string that might also appear inside another service's message.
- `-p err` returning `-- No entries --` is a genuinely useful result: it tells me that in this boot
  nothing at error level or worse was logged, so my cluster came up cleanly. Proving the absence of
  errors is something `grep` over a log file does badly.
- `--no-pager` matters in scripts and in `docker exec`. Without it `journalctl` pipes into `less`,
  which has no terminal to draw on and the command appears to hang.
- `journalctl` is the fastest way into a broken node. When a kubelet will not start,
  `journalctl -u kubelet -n 50` is the first command to run — I used exactly this pattern to confirm
  the kubelet and containerd were healthy after `kind create cluster`.
- The journal is capped and rotated (`--disk-usage` showed 8M here), so it is not a substitute for
  shipping logs off the node in a real deployment.

---

## Task 4: Linux command cheat sheet

### Files and directories

| Command | Purpose |
|---|---|
| `pwd` | Print the current directory |
| `ls -lah` | Long listing, hidden files, human readable sizes |
| `ls -li` | Listing with inode numbers (used in Task 1) |
| `cd -` | Jump back to the previous directory |
| `mkdir -p a/b/c` | Create a whole directory tree |
| `cp -r src dst` | Copy recursively |
| `mv old new` | Move or rename |
| `rm -rf dir` | Delete recursively without prompting |
| `ln f h` / `ln -s f s` | Hard link / symbolic link |
| `stat file` | Inode, size, permissions, timestamps |
| `tree -L 2` | Directory tree, two levels deep |
| `du -sh *` | Size of each entry in this directory |
| `df -h` | Free space per filesystem |

### Reading and searching

| Command | Purpose |
|---|---|
| `cat`, `less`, `head -n 20`, `tail -n 20` | Show file contents |
| `tail -f app.log` | Follow a file as it grows |
| `grep -rin "error" /var/log` | Recursive, case-insensitive search with line numbers |
| `find . -name "*.yaml" -mtime -1` | Files by name and modification time |
| `wc -l file` | Count lines |
| `sort file \| uniq -c \| sort -nr` | Frequency count, most common first |
| `awk '{print $1}'` / `cut -d: -f1` | Pull out a column |
| `sed -i 's/old/new/g' file` | In-place substitution |
| `diff -u a b` | Unified diff of two files |

### Permissions and ownership

| Command | Purpose |
|---|---|
| `chmod 644 file` / `chmod +x script.sh` | Numeric / symbolic permission change |
| `chown user:group file` | Change owner and group |
| `umask` | Default permission mask for new files |
| `sudo -i` | Interactive root shell |
| `id`, `whoami`, `groups` | Who am I and what am I a member of |
| `useradd -m -s /bin/bash u` / `adduser u` | Create a user (Task 2) |
| `passwd u`, `userdel -r u` | Set a password, delete a user and home |

### Processes and resources

| Command | Purpose |
|---|---|
| `ps -ef` / `ps aux` | Snapshot of all processes |
| `ps -eo pid,%mem,comm --sort=-%mem` | Processes sorted by memory (used in Topic 02) |
| `top`, `htop` | Live process view |
| `kill -15 PID` / `kill -9 PID` | Ask to stop / force stop |
| `pkill -f pattern`, `pgrep -f pattern` | Signal or find by command line |
| `jobs`, `fg`, `bg`, `cmd &` | Shell job control |
| `nohup cmd &` | Survive logout |
| `free -h`, `uptime`, `nproc` | Memory, load average, CPU count |
| `lsof -i :8080` | Which process holds a port |

### Services and logs (systemd)

| Command | Purpose |
|---|---|
| `systemctl status \| start \| stop \| restart <unit>` | Manage a service |
| `systemctl enable --now <unit>` | Start now and on every boot |
| `systemctl list-units --type=service --state=running` | What is running |
| `journalctl -u <unit> -n 50 --no-pager` | That service's recent logs (Task 3) |
| `dmesg \| tail` | Kernel messages |

### Archives, packages, networking

| Command | Purpose |
|---|---|
| `tar -czf a.tar.gz dir/` / `tar -xzf a.tar.gz` | Create / extract a gzipped tarball |
| `apt update && apt install -y pkg` | Install a package on Debian/Ubuntu |
| `apt list --installed \| grep pkg`, `dpkg -l` | Is it installed |
| `ip a`, `ip r` | Addresses and routes (modern replacement for `ifconfig`) |
| `ping -c 4 host`, `curl -I url`, `dig host` | Reachability, HTTP headers, DNS (Topic 03) |
| `ssh user@host`, `scp file user@host:/path` | Remote shell and copy |
| `history \| grep docker`, `Ctrl+R` | Find a command I ran before |
