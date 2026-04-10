# Dotfiles Repository - GNU Stow Environment

## What This Is

This is a **GNU Stow-based dotfiles repository** for managing development environment configurations across multiple machines. The goal: configure once, deploy anywhere.

## GNU Stow Basics

**GNU Stow** is a symlink farm manager. Each subdirectory here is a "package" that gets symlinked to `$HOME`.

**How it works:**
```bash
stow nvim    # Symlinks nvim/.config/nvim/* to ~/.config/nvim/*
stow zsh     # Symlinks zsh/.zshrc to ~/.zshrc
stow codex   # Symlinks codex/.codex to ~/.codex
```

The directory structure **inside each package** mirrors where files should go in `$HOME`.

## Key Principle

**Always edit files in this repository, not in `$HOME`.**

The files in `$HOME` are just symlinks pointing back here.

## Secrets and Machine-Specific Variables

**`~/.zshrc.local`** - NOT version controlled, NOT in this repo

This file is sourced at the end of `.zshrc` and should contain:
- API keys, tokens, secrets
- Machine-specific environment variables
- Private aliases or configurations

**Never add secrets to files in this repository. Always use `~/.zshrc.local`.**

## Guardrails

Do NOT perform the following without explicit user request:
- Read or modify `.env` files or any file containing secrets
- Run `ssh`, `rsync`, `scp`, or `sudo`
- Run `brew`, `docker`, `kubectl`, `terraform`, `cargo`, `go`, or `rustc`
- Modify system services (`crontab`, `launchctl`, `systemctl`)
- Change file permissions (`chmod`, `chown`)
- Force-push or run destructive git operations

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
3. Stow it: `stow newtool`
4. Update `install/modules/05-dotfiles.sh` to include it in automated installs

## Specs and Plans

- A **plan** shows **how** to implement a feature step by step.
- A **spec** defines **what** must always be true, regardless of implementation.
- Plans can change or be discarded; specs act as the enduring contract.
- Use specs to guide decisions, enforce correctness, and prevent accidental regressions.

## Important Reminders

- Stow creates symlinks, doesn't copy files
- The install script handles backups automatically
- Each machine can pull updates with `git pull` then `stow -R <package>` to restow
- Never commit secrets - use `~/.zshrc.local` instead
