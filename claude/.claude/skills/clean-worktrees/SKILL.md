---
name: clean-worktrees
description: Find the Claude-generated git worktrees (the ones under .claude/worktrees) in every repo under ~/unicity, show which are safe to delete and how much space they hold, and hand the user one command to remove them. Use only when the user runs /clean-worktrees.
argument-hint: "[folder, default ~/unicity]"
disable-model-invocation: true
allowed-tools: Bash(bash ~/.claude/skills/clean-worktrees/worktree-status.sh *)
---

# Clean up Claude worktrees

You check; the user removes. Never run `git worktree`, `remove-worktrees.sh`, `rm`, or anything else that
deletes a worktree folder or branch yourself — some repos (new-shop) forbid Claude from running `git worktree`.

## 1. Check

Use the folder in `$ARGUMENTS` if given, otherwise `~/unicity`:

```bash
bash ~/.claude/skills/clean-worktrees/worktree-status.sh ~/unicity
```

It is read-only. Each worktree comes back as:

- `REMOVE` — clean, everything pushed, no process running in it. Safe to delete.
- `KEEP` — has uncommitted changes, unpushed commits, a running process (dev server, Claude session), or is locked. Never removed.
- `STALE` — folder already deleted; only a leftover git record, cleared by the removal step.

## 2. Report

Show one table per repo: worktree, branch, verdict, and the reason (for `KEEP`) or size (for `REMOVE`).
Then the total space: give the "excluding node_modules" figure as the realistic estimate, because pnpm
shares most of `node_modules` with its store, and the full size as the upper bound.

If nothing is `REMOVE` or `STALE`, say so and stop.

## 3. Hand off removal

Tell the user to run this in the Claude prompt (the `!` runs it as them) or in their terminal, with the
same folder you checked:

```
! bash ~/.claude/skills/clean-worktrees/remove-worktrees.sh ~/unicity
```

It re-checks every worktree immediately before removing it, so anything that changed since step 1 is
skipped, not deleted. It uses `git worktree remove` without `--force`.

## 4. Confirm

When the output shows up, summarize the `REMOVED`, `SKIPPED`, `FAILED` and `PRUNED` lines and the space freed.
Mention that the `claude/*` branches are kept, and that the user can delete the merged ones in a repo with
this (`-d` refuses unmerged branches), filling in the repo folder:

```
! cd ~/unicity/<repo> && git branch --list 'claude/*' | xargs -n1 git branch -d
```
