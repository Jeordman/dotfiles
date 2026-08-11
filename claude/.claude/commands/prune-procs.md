# /prune-procs

Find dev processes that are marooned — hung node servers, language servers whose editor is gone, Playwright leftovers, dev servers rooted in worktrees that no longer exist — and offer them up for killing. **Always a picker: never kill anything the user did not explicitly select.**

## Arguments

`$ARGUMENTS` — optional focus. Empty means sweep everything.

- `/prune-procs` → full sweep
- `/prune-procs node` → only node/JS tooling
- `/prune-procs lsp` → only language servers
- `/prune-procs playwright` → only browser automation leftovers
- `/prune-procs 8080` → whatever is squatting on that port

## The actual problem

Listing processes is trivial; `ps` does it. The hard part is that a `next-server` eating 3G looks *byte-identical* in `ps` whether it is the dev server the user is actively hitting in a browser or the ghost of a worktree deleted two days ago. Name matching cannot tell those apart, and guessing wrong is expensive in one direction only: killing a live server interrupts real work, while leaving 200MB stranded for one more day costs nothing.

So the job is to gather **evidence** and only propose things you can point to a concrete reason for. If the only thing you can say about a process is "it's node and it's been up a while," that is not a finding — say nothing about it.

## Step 1 — gather evidence

Run these. Pass PIDs as literal comma-separated numbers you write out yourself; do not use shell variables to hold them.

**Memory hogs, user-owned, system noise stripped:**
```bash
ps -Ao pid,ppid,rss,etime,stat,tty,command -U "$USER" | grep -Ev '/System/|/usr/libexec/|/Library/(Apple|SystemExtensions|PrivilegedHelperTools)|/opt/jc/' | sort -k3 -rn | head -45
```

**Who is actually doing work right now:**
```bash
top -l 2 -n 25 -o cpu -stats pid,cpu,mem,command
```
Read only the **second** sample. This matters: the `%CPU` column in `ps` is an average over the process's entire lifetime, so a server that pegged a core for an hour and then wedged still reports a high number forever. `top`'s second sample is the only cheap instantaneous reading.

**Working directory for your shortlist** (this is usually the decisive signal):
```bash
lsof -a -d cwd -Fn -w -p 13757,13632,68377
```
Then check whether each path still exists. A process whose cwd was deleted is stranded by definition — nothing can be using it, because the thing it was serving is gone. For paths under a worktree, cross-check `git worktree list --porcelain`: a directory that still exists but is no longer registered was removed with `git worktree remove` and its dev server was left running.

Write the PID list out as literal digits. If any entry is empty or malformed, `lsof` discards the filter and dumps every process on the machine — several hundred lines of noise that buries the handful you actually asked about.

**Ports and live connections:**
```bash
lsof -nP -iTCP -a -w -p 13757,13632,68377
```
The `-a` is load-bearing and easy to drop. Selection flags in `lsof` are OR'd by default, so without it `-iTCP` and `-p` combine into "all TCP **or** these PIDs" and you get every socket on the machine — which reads as "everything has connections" and quietly makes the whole sweep return nothing.

`ESTABLISHED` means something is talking to it. One caveat: a dev server holds loopback connections to its **own** worker children (`127.0.0.1:58223->127.0.0.1:58224`), and those persist after it wedges. If every peer resolves to a PID inside the same process tree, that is internal chatter, not a user. Real evidence of use is a connection from outside the tree — a browser, a test runner, another machine.

## Step 2 — classify with evidence, not vibes

Split the signals. **Hard** evidence makes something a candidate on its own. **Soft** evidence only raises confidence in something already flagged — if you let soft signals promote, you will flag every daemon on the machine, because "idle for hours" is the normal resting state of correctly-working background software.

**Hard (any one qualifies):**
- cwd no longer exists on disk
- cwd is inside a worktree that `git worktree list` no longer knows about
- `PPID` is 1 **and** it is a shell-child kind of program (node, esbuild, turbo, a language server, playwright, a test runner) — its parent died and launchd adopted it
- listening on a port with zero connections for over ~30 minutes and no CPU
- RSS has collapsed to 0 while still running

**Soft (confidence only):**
- zero CPU for hours
- no owning shell or editor in its ancestry
- port open but idle
- duplicate of another process with the same command and same project root

**Two traps that produce false positives — check both before flagging anything:**

1. **`PPID 1` does not mean orphaned.** Daemons deliberately detach via `setsid()` and legitimately sit at PPID 1 forever. The discriminator is the `s` flag in `STAT` (`Ss`, `SNs`): that marks a *session leader*, meaning the process detached on purpose. A dev tool orphaned when its shell died keeps its original session ID and never gains that flag. On this machine `claude daemon run`, `claude bg-pty-host`, and `herdr server` all sit at PPID 1 with `Ss` — they are infrastructure, not garbage. Never propose them.

2. **Login shells appear as `-zsh`, with a leading dash.** When walking a parent chain to decide whether something has a live owner, strip that dash or you will conclude a perfectly healthy `claude` session running in a cmux tab has no parent and is abandoned.

**Disqualify outright** — do not list these at all, at any confidence:
- anything with an ESTABLISHED connection from outside its own process tree
- anything burning real CPU in `top`'s second sample
- anything whose ancestry reaches a live nvim, shell, cmux, Ghostty, tmux, claude, or codex
- your own ancestry: walk up from the shell you are running in and exclude every PID on that chain, or you will offer to kill the session having this conversation
- GUI apps under `/Applications` (headless browsers under `~/Library/Caches/ms-playwright` are fair game — those are Playwright leftovers, not apps the user opened)

**Zombies (`Z` in STAT) are not killable.** They are already dead and hold no memory; only the parent can reap them. Do not put them in the picker. If there are several, mention the leaking parent in one line, because that parent is the real bug.

**Prefer parents over children.** A turbo dev tree is ~25 processes; killing the root `pnpm turbo run dev` takes all of them. Offering 25 separate rows for one decision is noise. Group a tree into one row, note the child count and the tree's total RSS, and kill the root.

## Step 3 — present the picker

Show a compact table, highest confidence first, with a running memory total. Keep the "why" to the specific evidence — the user is deciding based on that column, so a vague reason is a useless row.

```
#   PID      RAM    AGE   PROCESS                      WHY IT LOOKS MAROONED
1   13757    2.9G   14h   next-server (+7 children)    cwd deleted: .../feat-ECOM-6421
2   41022    780M   2d    vtsls language server        orphaned — nvim 40988 is gone
3   68377    410M   6h    playwright-mcp               orphaned, port 9223 idle 6h
4   13799    31M    14h   esbuild ×3                   orphaned — parent turbo died
                   ─────
                    4.1G reclaimable

Keeping 22 others (live turbo tree in feat-ECOM-6613, 3 connections).
```

Then ask which to kill, with `all` as an option. Accept numbers, ranges, or "all". If nothing qualifies, say so plainly in one line and stop — a clean machine is a valid, common result, and inventing marginal candidates to fill the table trains the user to stop trusting it.

Flag anything that holds unrecoverable state in the row itself. A `claude` or `codex` process loses its conversation history when killed, unlike a dev server that restarts in three seconds — that asymmetry should be visible at the moment of choosing, not buried in a footnote.

## Step 4 — kill

`SIGTERM` first, wait ~3 seconds, then `SIGKILL` only what survived:

```bash
kill 13757 41022 68377
sleep 3
kill -9 13757 41022 68377 2>/dev/null
ps -o pid= -p 13757,41022,68377
```

TERM before KILL is what lets a dev server tear down its own children; going straight to KILL just orphans the next generation and recreates the mess you are cleaning.

Report what died and the actual memory reclaimed, then stop. If something refused to die, name it — a process that survives KILL is stuck in an uninterruptible syscall and needs a different fix, which is worth knowing rather than silently omitting.
