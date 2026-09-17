# Topic 04 – Git and GitHub

**Name:** Dhruv Davda
**Roll No:** 24BCS10203
**Email:** Dhruv.24bcs10203@sst.scaler.com
**Group:** A

Both tasks were practised in a throwaway repository so that I could create and destroy history
freely. The files the exercises produced are kept in [`demo-files/`](./demo-files) as evidence.

```bash
git init
git config user.name "Dhruv Davda"
git config user.email "Dhruv.24bcs10203@sst.scaler.com"
```

---

## Task 1: `git commit -m` vs `git commit -a -m`

### The difference

| | `git commit -m "msg"` | `git commit -a -m "msg"` |
|---|---|---|
| What gets committed | Only what is **already staged** with `git add` | Staged changes **plus all modifications to tracked files** |
| Modified tracked files | Ignored unless staged | Included automatically |
| **Untracked (new) files** | Ignored | **Still ignored** |
| Deleted tracked files | Ignored unless `git rm`/staged | Included |
| Staging area | Respected exactly | Bypassed for tracked files |
| Good for | Partial commits, splitting work up | Quick commits when you want everything you edited |

The one line worth memorising: **`-a` means "all tracked files", not "all files".**

### Practice

Starting point — one committed file, then I modify it *and* add a brand new file:

```console
$ echo "line 1" > notes.txt && git add notes.txt && git commit -m "Add notes.txt"
5a57739 Add notes.txt

$ echo "line 2" >> notes.txt      # modification to a TRACKED file
$ echo "brand new" > extra.txt    # a NEW, untracked file

$ git status --short
 M notes.txt
?? extra.txt
```

The two status codes matter: `M` in the second column means modified but **not staged**, and `??`
means git has never seen this file before.

Attempt 1, without `-a` and with nothing staged:

```console
$ git commit -m "Try without -a"
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   notes.txt

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	extra.txt

no changes added to commit (use "git add" and/or "git commit -a")
```

**No commit was created.** The staging area was empty, so there was nothing to record — git even
suggests the two ways forward in its last line.

Attempt 2, with `-a`:

```console
$ git commit -a -m "Update notes.txt via -a"
[main 5b27492] Update notes.txt via -a
 1 file changed, 1 insertion(+)

$ git status --short
?? extra.txt

$ git show --stat --oneline HEAD
5b27492 Update notes.txt via -a
 notes.txt | 1 +
 1 file changed, 1 insertion(+)
```

### What I observed

- `git commit -m` with an empty index does **nothing at all** — it is not an error that loses work,
  but it is easy to believe you committed when you did not. Reading the output matters.
- `-a` committed `notes.txt` without me running `git add`, because that file was already tracked.
- **`extra.txt` survived as `??` even after `-a`.** This is the trap: `-a` is short for
  `--all`, which reads as "everything", but git means "all *tracked* files". A newly created file —
  a new source file, a new manifest — needs an explicit `git add` no matter what.
- `git show --stat` confirms the commit contains exactly one file, which is how I verified the claim
  rather than assuming it.
- Practical rule I settled on: use `git add -p` / `git add <file>` then plain `git commit` when a
  change should be split into meaningful commits, and `git commit -am` only for small edits to files
  git already knows about. Either way, `git status` before committing costs nothing.

---

## Task 2: `git cherry-pick`

`git cherry-pick <commit>` takes the **diff introduced by one commit** and replays it on the current
branch as a **new commit with a new hash**. It is the tool for "I need that one fix here", as opposed
to `merge`, which brings a whole branch's history along.

### Steps

Three commits on a `feature` branch, of which I only want the middle one:

```console
$ git checkout -b feature
feature

$ git log --oneline --all --graph
* e43b3e8 feature: add logout
* 9710353 feature: add validation
* c739912 feature: add login
* 5b27492 Update notes.txt via -a
* 5a57739 Add notes.txt
```

Back on `main`, only the earlier files exist:

```console
$ git checkout main
main
$ ls
extra.txt
notes.txt
```

Now pick just `9710353`:

```console
$ git cherry-pick 9710353
[main 2d109fb] feature: add validation
 Date: Thu Sep 17 20:42:40 2026 +0530
 1 file changed, 1 insertion(+)
 create mode 100644 validation.txt

$ ls
extra.txt
notes.txt
validation.txt

$ git log --oneline
2d109fb feature: add validation
5b27492 Update notes.txt via -a
5a57739 Add notes.txt
```

The graph afterwards is the whole lesson in one picture:

```console
$ git log --oneline --graph --all
* e43b3e8 feature: add logout
* 9710353 feature: add validation
* c739912 feature: add login
| * 2d109fb feature: add validation
|/
* 5b27492 Update notes.txt via -a
* 5a57739 Add notes.txt
```

### Handling a conflict

Cherry-picking is only interesting when the target branch has moved on, so I set up a collision on
purpose — the same file written with a different value on each branch:

```console
$ git log --oneline -1   # on feature
86f03e4 feature: set timeout to 30
$ git log --oneline -1   # on main
7f4c465 main: set timeout to 99

$ git cherry-pick 86f03e4
Auto-merging config.txt
CONFLICT (add/add): Merge conflict in config.txt
error: could not apply 86f03e4... feature: set timeout to 30
hint: After resolving the conflicts, mark them with
hint: "git add/rm <pathspec>", then run
hint: "git cherry-pick --continue".
hint: You can instead skip this commit with "git cherry-pick --skip".
hint: To abort and get back to the state before "git cherry-pick",
hint: run "git cherry-pick --abort".

$ git status --short
AA config.txt
?? extra.txt

$ cat config.txt
<<<<<<< HEAD
timeout=99
=======
timeout=30
>>>>>>> 86f03e4 (feature: set timeout to 30)
```

Resolving it by keeping the incoming value, then finishing the pick:

```console
$ echo "timeout=30" > config.txt && git add config.txt
$ git cherry-pick --continue
[main 2a5fd89] feature: set timeout to 30
 Date: Thu Sep 17 20:42:52 2026 +0530
 1 file changed, 1 insertion(+), 1 deletion(-)

$ git log --oneline -3
2a5fd89 feature: set timeout to 30
7f4c465 main: set timeout to 99
2d109fb feature: add validation
$ cat config.txt
timeout=30
```

### What I observed

- **The commit hash changed.** `9710353` on `feature` became `2d109fb` on `main`. The *content* of
  the change is identical but a commit's hash covers its parent and timestamp too, so replaying a
  change necessarily produces a different commit. The graph shows the same subject line existing
  twice, on two diverging lines of history.
- The commits I did not pick — `add login` and `add logout` — never arrived. `ls` on `main` shows
  `validation.txt` but no `login.txt`. A merge would have brought all three.
- Cherry-pick **preserves the original author and author date** (note the extra `Date:` line in the
  output) while setting a new committer. That is why `git log` on main showed a commit dated from
  the feature branch's timeline.
- `CONFLICT (add/add)` is specifically "both sides created this file". The conflict markers separate
  `HEAD` (what is already on the branch I am on) from the incoming commit, and getting that
  direction right is the difference between keeping and discarding the change you meant to apply.
- Mid-conflict the repository is in a **special cherry-pick state** with three ways out —
  `--continue` after `git add`, `--skip` to drop that commit, `--abort` to rewind to before the
  pick. `--abort` is the safe escape hatch: nothing is lost.
- Other useful forms: `git cherry-pick A..B` for a range, `-n` to apply without committing so I can
  inspect first, and `-x` to append a `(cherry picked from commit ...)` line to the message — well
  worth it when backporting a fix to a release branch, since it records where the change came from.
- The honest downside: the same logical change now exists as two commits. If `feature` is merged
  into `main` later, git usually works out that the patch is already present, but a duplicated
  commit is exactly the kind of thing that makes history hard to read. Cherry-pick is for hotfixes
  and backports, not a substitute for merging.
