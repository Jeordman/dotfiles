---
description: Remove worktrees safely with commit/push validation
allowed-tools: Bash
argument-hint: "all or specific worktree names"
---

# 🧹 Worktree Removal Tool

Safely remove worktrees. Only removes worktrees with clean, pushed code. Everything runs in the foreground with full visibility.

## Quick start:

Tell me which worktrees to remove:
- **"all"** - Remove all clean worktrees
- **"worktree-name"** - Remove specific worktree(s)

---

## What I'll do:

**For each worktree:**
1. Check if it has uncommitted changes
2. Check if all commits are pushed to origin
3. Skip if unsafe (you'll see why)
4. If safe, remove (in order):
   - Kill any tmux session matching the worktree name
   - Remove worktree directory
   - Clean up git references
5. Never touch the main repo

**Important:** When removing a worktree, I will:
- Run `tmux kill-session -t WORKTREE_NAME` to stop any running session
- Run `git worktree remove PATH` to clean up
- Verify the directory is deleted

**Hard stops:**
- Working directory is dirty → Stop and tell you to commit/push

**Adaptive handling:**
- Worktree already deleted → Skip, note it
- Uncommitted changes → Skip, tell you what's pending
- Unpushed commits → Skip, show what's unpushed
- Prunable worktree → Remove it safely
- Main repo detected → Skip it, protect it

---

## Step 1: Scanning projects

! pwd
! ls -1 -d */ 2>/dev/null

---

## Step 2: Tell me what to remove

Provide your choice:
- "all"
- "ClimbSmarter-feat-WHAT-2234-eyo-this-work"
- "ClimbSmarter-fix-TEST-2222 ClimbSmarter-feat-ECOM-1234"

I'll handle validation and removal in the foreground so you see everything happening!
