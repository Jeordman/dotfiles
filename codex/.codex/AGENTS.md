# Global Agent Instructions

## Dotfiles Repository - GNU Stow Environment

This repository uses **GNU Stow** to manage development environment configurations. Each subdirectory is a "package" that gets symlinked to `$HOME`.

**Always edit files in the dotfiles repository, not in `$HOME`.** The files in `$HOME` are symlinks pointing back here.

## Secrets and Machine-Specific Variables

`~/.zshrc.local` is NOT version controlled and should contain:
- API keys, tokens, secrets
- Machine-specific environment variables
- Private aliases or configurations

**Never add secrets to files in this repository. Always use `~/.zshrc.local`.**

## Guardrails

The following operations should **never** be performed without explicit user request:
- Reading or modifying `.env` files or any file containing secrets
- Running `ssh`, `rsync`, `scp`, or `sudo`
- Running `brew`, `docker`, `kubectl`, `terraform`, `cargo`, `go`, or `rustc`
- Modifying system services (`crontab`, `launchctl`, `systemctl`)
- Changing file permissions (`chmod`, `chown`)
- Force-pushing or destructive git operations

## Specs and Plans

- A **plan** shows **how** to implement a feature step by step.
- A **spec** defines **what** must always be true, regardless of implementation.
- Plans can change or be discarded; specs act as the enduring contract.
- Use specs to guide decisions, enforce correctness, and prevent accidental regressions.
- If a `{feature_name}.spec.md` exists, treat it as authoritative. Plans must not contradict specs.

## Conventions

- Stow creates symlinks, doesn't copy files
- Each machine can pull updates with `git pull` then `stow -R <package>` to restow
- The install script (`install.sh`) handles backups automatically
- Never commit secrets - use `~/.zshrc.local` instead
