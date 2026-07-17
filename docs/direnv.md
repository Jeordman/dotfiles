# direnv — per-directory environment variables

`direnv` lets a folder (and everything under it) automatically set/unset
environment variables when you `cd` into it, via an `.envrc` file. When you
leave the folder, the variables are removed. Nothing is global; the change is
scoped to the directory tree.

The first use case here: point a folder at a **different Claude Code account**
by overriding `CLAUDE_CONFIG_DIR` only inside that folder.

## How it works, step by step

1. **The shell hook.** `zsh/.zshrc` ends with:

   ```zsh
   eval "$(direnv hook zsh)"
   ```

   This registers a hook that runs on every prompt / directory change. On each
   `cd`, direnv checks whether the current (or any parent) directory contains an
   `.envrc`.

2. **The `.envrc` file.** A plain shell script living in the target folder. It
   is *sourced* by direnv, and any variables it `export`s are injected into your
   shell while you're inside that directory. Example (in `~/personal/.envrc`):

   ```zsh
   export CLAUDE_CONFIG_DIR="$HOME/.claude-personal"
   ```

3. **Trust (`direnv allow`).** direnv will **not** load an `.envrc` until you
   explicitly approve it — this stops a repo you cloned from silently running
   code in your shell. Approve once with:

   ```zsh
   direnv allow ~/personal      # or just `direnv allow` while inside it
   ```

   You must re-run `direnv allow` **every time the `.envrc` changes**. Until then
   direnv refuses to load it and warns `direnv: error .envrc is blocked`.

4. **Enter / leave.**
   - `cd ~/personal` → you see `direnv: loading ~/personal/.envrc` and
     `CLAUDE_CONFIG_DIR` is now set. This also applies to every subdirectory.
   - `cd` back out → direnv unloads it and `CLAUDE_CONFIG_DIR` is unset again.

   Verify without even relying on the shell hook:

   ```zsh
   direnv exec ~/personal sh -c 'echo $CLAUDE_CONFIG_DIR'
   # → /Users/<you>/.claude-personal
   ```

## Why this switches Claude accounts

Claude Code reads its login, settings, history, etc. from the directory named
by `CLAUDE_CONFIG_DIR` (default: `~/.claude`). Pointing it at a separate dir
(`~/.claude-personal`) gives that folder its own isolated Claude state — a
different logged-in account — while the rest of your machine keeps using
`~/.claude`. So:

```zsh
cd ~/personal
claude            # then /login → stored under ~/.claude-personal
```

> **macOS caveat:** on macOS, Claude Code credentials are stored in the
> **Keychain**, not in a file inside the config dir (that's why there's no
> `.credentials.json` in `~/.claude`). The docs only clearly state that
> `CLAUDE_CONFIG_DIR` relocates the *file-based* credentials on Linux/Windows.
> After your first `/login` in `~/personal`, confirm it actually logged in as
> the *other* account and left your main account intact. If the Keychain login
> turns out to be shared, fall back to an `ANTHROPIC_API_KEY` / `apiKeyHelper`
> in that folder instead.

## What lives where

| Piece | Location | In the repo? |
|-------|----------|--------------|
| direnv shell hook | `zsh/.zshrc` (`eval "$(direnv hook zsh)"`) | ✅ tracked |
| direnv install | `install/modules/03-terminal.sh` (`ensure_package "direnv" ...`) | ✅ tracked |
| The `.envrc` | `~/personal/.envrc` | ❌ per-location, not tracked |
| The alt account state | `~/.claude-personal/` | ❌ runtime + secrets, never committed |

The `.envrc` is **not** stored in this dotfiles repo on purpose: it's specific
to one absolute path on one machine, and a config dir is almost entirely
runtime state and credentials. This mirrors how `~/.claude` itself works — only
curated config (`commands`, `skills`, `settings.json`, …) is stowed in from
`claude/.claude/`; the rest lives only in the home directory.

## Sharing config with the personal account

A fresh `CLAUDE_CONFIG_DIR` is a **blank slate** — switching to
`~/.claude-personal` bypasses all your user-scope config, so by default the
personal account has **none** of your skills, commands, agents, hooks, settings,
or statusline (built-in commands/agents and any project-level `.claude/` +
`CLAUDE.md` still work, because those don't come from the config dir).

To make the personal account inherit your setup, `install/modules/05-dotfiles.sh`
runs `link_personal_claude_config()`, which symlinks the **same dotfiles sources**
that `~/.claude` uses into `~/.claude-personal`:

| Item | Symlinked to | Source |
|------|--------------|--------|
| `skills`, `commands`, `hooks`, `scripts`, `settings.json`, `statusline-command.sh` | `dotfiles/claude/.claude/…` | tracked (shared with main account) |
| `agents` | `~/.claude/agents` | local (not in dotfiles) |

What stays **separate** per account (by design): the **login** and **MCP
servers** (stored in each config dir's `.claude.json`, tied to that account's
auth) — you set those up once per account. `plugins` are also per config dir.

> Sharing is safe because `settings.json` contains no auth keys
> (`apiKeyHelper` / `ANTHROPIC_API_KEY`); if it did, it would override the
> personal login. Re-run the linker any time by sourcing the module or running
> `./install.sh` again — it's idempotent and backs up any real file it would
> replace.

## Requirements / install

- direnv is installed by `./install.sh` (see `03-terminal.sh`), or manually:
  `brew install direnv`.
- The hook in `zsh/.zshrc` activates it. Open a new terminal or
  `source ~/.zshrc` after a fresh install.

## Add another per-folder account (or any per-folder env)

```zsh
echo 'export CLAUDE_CONFIG_DIR="$HOME/.claude-work"' > ~/work/.envrc
direnv allow ~/work
cd ~/work && claude   # /login with that account
```

The same pattern works for any environment variable you want scoped to a
project — API keys, `NODE_ENV`, tool config, etc.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `direnv: error .envrc is blocked` | Run `direnv allow` in the folder (needed after every edit). |
| No `direnv: loading …` on `cd` | Hook not active — open a new terminal or `source ~/.zshrc`; confirm `command -v direnv`. |
| Variable not set | Check you're *inside* the folder: `direnv status` and `echo $CLAUDE_CONFIG_DIR`. |
| Claude still uses the main account | See the macOS Keychain caveat above. |
