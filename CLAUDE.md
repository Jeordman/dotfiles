# Dotfiles Repository - GNU Stow Environment

## What This Is

This is a **GNU Stow-based dotfiles repository** for managing development environment configurations across multiple machines. The goal: configure once, deploy anywhere.

## GNU Stow Basics

**GNU Stow** is a symlink farm manager. Each subdirectory here is a "package" that gets symlinked to `$HOME`.

**How it works:**
```bash
stow nvim    # Symlinks nvim/.config/nvim/* to ~/.config/nvim/*
stow zsh     # Symlinks zsh/.zshrc to ~/.zshrc
stow claude  # Symlinks claude/.claude to ~/.claude
```

The directory structure **inside each package** mirrors where files should go in `$HOME`.

## Key Principle

**Always edit files in this repository, not in `$HOME`.**

- ❌ Wrong: Edit `~/.zshrc` directly
- ✅ Right: Edit `~/dotfiles/zsh/.zshrc`

The files in `$HOME` are just symlinks pointing back here.

## Secrets and Machine-Specific Variables

**`~/.zshrc.local`** - NOT version controlled, NOT in this repo

This file is sourced at the end of `.zshrc` (line 150) and should contain:
- API keys, tokens, secrets
- Machine-specific environment variables
- Private aliases or configurations

**Important:** Never add secrets to files in this repository. Always use `~/.zshrc.local`.

## Installation System

**`install.sh`** orchestrates everything:
- Installs tools and dependencies
- Runs `stow` to create all symlinks
- Creates backups of existing configs (with timestamps)
- Idempotent - safe to run multiple times

**Modes:**
- `./install.sh` - Interactive prompts
- `./install.sh --all` - Install everything
- `./install.sh --minimal` - Core tools only
- `./install.sh --dry-run --all` - Preview without changes

## Adding New Configurations

1. Create package directory with proper structure:
   ```bash
   mkdir -p newtool/.config/newtool
   ```

2. Add your config files inside it

3. Stow it:
   ```bash
   stow newtool
   ```

4. Update `install/modules/05-dotfiles.sh` to include it in automated installs

## Claude Code Integration

The `claude/` package contains custom slash commands in `claude/.claude/commands/` and skills in `claude/.claude/skills/`.

When stowed, these become available in Claude Code across all projects.

### Specs and Plans
- A plan shows **how** to implement a feature step by step.
- A spec defines **what** must always be true, regardless of implementation.
- Plans can change or be discarded; specs act as the enduring contract.
- Use specs to guide decisions, enforce correctness, and prevent accidental regressions.

### Agent Orchestration (Claude + Codex)

Codex is registered as an MCP server for Claude Code (see `install/modules/05-dotfiles.sh`). This means Claude can call Codex directly as a tool — no separate terminal tab required.

**The split**:
- **Claude drives.** It holds the pen for implementation, planning, and explanation.
- **Codex is consulted.** It's a different model family with different blind spots, used as a second opinion on high-value work.

**When Codex runs** (all explicit — no skill auto-triggers Codex anymore):
- `/codex-review` — explicit code review of the current diff (dumps Codex output raw, then Claude adds notes).
- `/codex-plan-review` — explicit gap analysis of a plan file (appends findings to the plan).
- `/debate-plan` — Claude and Codex each produce an initial plan in parallel, then debate back-and-forth under a Team Lead (main Claude) for up to 3 rounds until consensus, then emit a combined plan. Includes a pre-flight warning if either agent is above 60% of its current usage window.

**Cost discipline**: Codex calls aren't free. All Codex invocation is now explicit via slash command — the user decides when a second opinion is worth it. `/debate-plan` caps at 3 debate rounds (≤4 Codex calls total) and pre-flights usage before firing.

## Important Reminders

- Stow creates symlinks, doesn't copy files
- The install script handles backups automatically
- Each machine can pull updates with `git pull` then `stow -R <package>` to restow
- Never commit secrets - use `~/.zshrc.local` instead
