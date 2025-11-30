---
description: Initialize a worktree with feature branch and tmux session for parallel development
allowed-tools: Bash
argument-hint: "project base-branch feat/fix ticket description"
---

# 🚀 Worktree Initialization

I'll create a feature branch, git worktree, and tmux session for development with full visibility.

## Process:

1. **Validate** your inputs (format checks)
2. **Summarize** what will be created
3. **Confirm** you want to proceed
4. **Execute** everything in the foreground so you see it all

---

## Quick Start

Provide all details in ONE message:

**"ClimbSmarter main feat ECOM-1234 checkout-flow"**

---

## Step 1: Input Validation

**Provide ALL of these:**

1. **Project name** (e.g., `ClimbSmarter`, `new-shop`)
2. **Base branch** (e.g., `main`, `staging`, `release`, `master`)
3. **Type** (`feat` or `fix`)
4. **Ticket** (format: `WORD-XXXX`, e.g., `ECOM-1234`)
5. **Description** (kebab-case, e.g., `checkout-flow`)

**Format:** "ClimbSmarter main feat ECOM-1234 add-training-log"

Once you provide these, I'll validate the format and move to Step 2 (Summary).

---

## Execution Instructions

When executing, I will:

1. **Validate inputs** - Check ticket format (WORD-XXXX) and description (kebab-case)
2. **Verify repo** - Confirm the project directory exists and is a git repo
3. **Check status** - Ensure working directory is clean (no uncommitted changes)
4. **Create branch** - Create the feature branch locally: `git checkout -b BRANCH_NAME`
5. **Checkout base branch** - Return to the base branch before creating worktree: `git checkout BASE_BRANCH`
6. **Create worktree** - Create worktree as SIBLING (using `../` path): `git worktree add ../PROJECT-TYPE-TICKET-DESC BRANCH_NAME`
7. **Copy env files** - Copy `.env` and `.env.local` to the new worktree
8. **Initialize tmux** - Run `dev-init -d WORKTREE_PATH -s` to set up the session
9. **Attach** - You'll be in the new tmux session

**Key:** All paths must be absolute or relative from the unicity root to ensure worktrees are siblings, not subdirectories.

---

## Adaptive Behavior

I'll handle edge cases intelligently:

**Hard stops (will fail):**
1. **Project doesn't exist** - Can't proceed without a valid git repo
2. **Working tree is dirty** - Stash or commit changes first

**Adaptive handling (will continue):**
1. **Branch already exists locally** - Skip creation, use the existing branch
2. **Worktree already exists** - Ask if you want to reuse it or pick a new name
3. **Env files don't exist** - Skip copying, continue without them
4. **No .env files found** - Just note it and proceed

This way, running the command multiple times or with existing branches won't cause failures.
