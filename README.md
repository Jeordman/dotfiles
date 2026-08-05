# Dotfiles

Personal development environment configuration with automated installation.

## Quick Start

### 1. Clone the Repository

```bash
cd ~
git clone <your-dotfiles-repo-url> dotfiles
cd dotfiles
```

### 2. Run the Installation Script

**Interactive mode** (recommended for first-time setup):
```bash
./install.sh
```

**Install everything** (automated):
```bash
./install.sh --all
```

**Preview installation** (dry-run):
```bash
./install.sh --dry-run --all
```

**Core tools only** (minimal setup):
```bash
./install.sh --minimal
```

## What Gets Installed

### Core System Tools (01-system.sh)
- GNU Stow (dotfile management)
- Git
- curl
- Build essentials (Linux only)

### Development Tools (02-development.sh)
- Neovim
- ripgrep (fuzzy search)
- fzf (fuzzy finder)
- fd (fast find)
- lazygit (git UI)
- jq (JSON processor)
- GitHub CLI (gh)
- Playwright MCP (for Claude Code front-end automation)

### Terminal Enhancements (03-terminal.sh)
- **Zsh** with Oh My Zsh
- **Tmux** with TPM (plugin manager)
- **NVM** (Node Version Manager) + Node.js LTS
- **Modern CLI tools**:
  - bat (better cat)
  - eza (better ls)
  - zoxide (smart cd)
  - delta (better git diff)
  - thefuck (command correction)
- **Zsh plugins**:
  - zsh-autosuggestions
  - zsh-syntax-highlighting
  - Powerlevel10k theme

### Dotfiles Linking (05-dotfiles.sh)
- Symlinks all configs using GNU Stow
- Creates timestamped backups of existing configs
- Detects and clears conflicting files before stowing (stow is all-or-nothing:
  one collision aborts every package, which silently leaves nvim/zsh/tmux unlinked)
- Supports: bin, btop, claude, git, hunk, nvim, tmux, tuicr, yazi, zsh
  (plus ghostty, herdr, codex, lazygit on macOS)

### Shell configuration

zsh is the only configured shell — `zsh/.zshrc`, with oh-my-zsh and
powerlevel10k installed by `03-terminal.sh`. There is deliberately no bash
config: keeping a second shell at parity means every alias and function has to
be written in the common subset of both languages, which costs more than it
saves on machines where `03-terminal.sh` does its job.

`~/.zshrc` degrades gracefully when oh-my-zsh is missing (a half-finished
install, or a box with only the bare zsh binary): it warns, falls back to a
`vcs_info` prompt, and still loads every alias, function and keybinding. Without
that guard the shell dies at the `source` and you get none of your config.

## Usage Examples

### Interactive Installation
```bash
./install.sh
```
Prompts you to choose which categories to install.

### Full Automated Installation
```bash
./install.sh --all
```
Installs everything without prompts.

### Non-Interactive Mode
```bash
NON_INTERACTIVE=1 ./install.sh --all
```
Perfect for automation/CI - no prompts.

### Dry Run
```bash
./install.sh --dry-run --all
```
See what would be installed without making changes.

## Manual Installation

If you prefer to install specific components manually:

```bash
# Install GNU Stow first
brew install stow  # macOS
# or: sudo apt install stow  # Ubuntu/Debian

# Link specific configs
cd ~/dotfiles
stow nvim        # Link neovim config
stow tmux        # Link tmux config
stow zsh         # Link zsh config
stow ghostty     # Link ghostty config
stow yazi        # Link yazi config
stow claude      # Link claude config
stow bin         # Link bin scripts

# Or link everything at once
stow bin btop claude git hunk nvim tmux tuicr yazi zsh

# NOTE: stow is all-or-nothing. If any target already exists as a real file
# (Claude Code writes ~/.claude/settings.json on first launch, for example),
# stow aborts the ENTIRE batch and links nothing. Check with:
#   stow -n -v <packages>
# install.sh handles this automatically by backing up conflicts first.
```

## Fresh machine, one run

On a new Ubuntu box the intended flow is: add your SSH key to GitHub, clone this
repo, run `./install.sh --all`. A single run is meant to be enough — these used
to require a second pass or manual work and no longer do:

| Was broken | Fix |
|---|---|
| `tree-sitter` / `codex` skipped ("needs npm") | `02-development.sh` runs before nvm exists, so npm-backed installs are **queued** and flushed by `03-terminal.sh` once Node is up |
| `yazi` needed a Rust toolchain | Installs the prebuilt release binary (plus `ya`) into `~/.local/bin` |
| `poppler` "Unable to locate package" | apt wants `poppler-utils`; brew wants `poppler` |
| `lazygit` "no release asset found" | Upstream lowercased its asset names; matching is now case-insensitive |
| stow silently linked nothing | Conflicting targets are backed up before stowing |
| oh-my-zsh overwrote `~/.zshrc` | Installer now runs with `--keep-zshrc` |

Still genuinely manual, because they need secrets or a human:

- `gh auth login`
- `~/.gitconfig.local` (your name/email — deliberately untracked)
- tmux plugins: `Ctrl-Space + I`
- `p10k configure`, **then commit the result** so the prompt follows you:
  ```bash
  mv ~/.p10k.zsh ~/dotfiles/zsh/.p10k.zsh && cd ~/dotfiles && stow -R zsh
  ```

## Post-Installation

1. **Restart your terminal** or run:
   ```bash
   exec zsh
   ```
   Don't `source ~/.zshrc` from bash — zsh syntax isn't valid bash and it fails
   with `bad substitution` and `autoload: command not found`.

2. **Set zsh as default shell** (if not done automatically):
   ```bash
   chsh -s $(which zsh)
   ```
   The installer attempts this, then retries with `sudo chsh`. Both can still
   fail: `chsh` authenticates via PAM, so on an SSH-key-only account with no
   usable password it returns `PAM: Authentication failure` even with the right
   password. Check what actually took effect:
   ```bash
   getent passwd "$USER" | cut -d: -f7
   ```
   and if it isn't zsh:
   ```bash
   sudo chsh -s $(which zsh) "$USER"
   ```
   This matters — until it's set you log into bash, which this repo does not
   configure at all.

3. **Install tmux plugins**:
   - Open tmux
   - Press `Ctrl-Space + I` (capital I)

4. **Verify neovim setup**:
   ```bash
   nvim
   :checkhealth
   ```

5. **Configure Powerlevel10k** (if first time):
   ```bash
   p10k configure
   ```

6. **Set up Claude Code MCP** (if using Claude Code):
   - The installation script installs Playwright MCP globally
   - Configure it in Claude Code with:
     ```bash
     claude mcp add --scope user --transport stdio playwright -- npx -y @playwright/mcp@latest
     ```
   - Verify installation:
     ```bash
     claude mcp list
     ```
   - You should see `playwright (stdio) - connected`
   - This enables Claude Code to use Playwright for front-end automation and testing

## Claude Code Commands

This dotfiles repo includes custom slash commands for Claude Code integration:

### `/wtn` - Create feature branch with worktree and tmux session

Initialize a new git worktree with a feature branch and tmux session for parallel development.

**Usage:**
```bash
/wtn <project> <base-branch> <type> <ticket> <description>
```

**Example:**
```bash
/wtn ClimbSmarter main feat ECOM-1234 checkout-flow
```

**What it does:**
1. Creates a feature branch: `feat/ECOM-1234-checkout-flow`
2. Creates a git worktree as a sibling directory
3. Copies `.env` and `.env.local` files
4. Initializes a tmux session for the worktree
5. Attaches you to the new tmux session

### `/wtr` - Safely remove worktrees

Remove one or more worktrees, but only if code is committed and pushed.

**Usage:**
```bash
/wtr <name-or-all>
```

**Examples:**
```bash
/wtr all                                    # Remove all clean worktrees
/wtr ClimbSmarter-feat-ECOM-1234-checkout  # Remove specific worktree
```

**Safety checks:**
- Prevents deletion of worktrees with uncommitted changes
- Prevents deletion of worktrees with unpushed commits
- Kills associated tmux sessions automatically
- Protects main repository from accidental deletion

### `/plan-feature` - Interactive feature planning and documentation

Plan and document large features interactively before implementing them. This command helps you think through architecture, identify affected files, and create a comprehensive implementation roadmap.

**Usage:**
```bash
/plan-feature
```

Then describe your feature when prompted.

**Example:**
```
You: /plan-feature

Claude: What feature would you like to plan?

You: A subscription management dashboard where users can view, pause, resume, and cancel their subscriptions

Claude: Great! Let me explore your codebase to understand the current architecture...
[Explores state management, existing patterns, API structure]

Claude: I found you're using Zustand for state management. I have some questions:
1. Should this be a new route or integrate into existing settings?
2. Do you want real-time subscription status updates?
3. Should we use optimistic UI updates for pause/resume actions?

[You answer questions]

Claude: Here's the Overview section for the plan:
## Overview
[Detailed overview based on your answers and codebase analysis]

Should I add this to the markdown file?

You: Yes

Claude: Added! Now here's the Files to Create section...
```

**What it does:**
1. Asks clarifying questions about requirements
2. Explores your codebase to understand existing patterns
3. Presents each section of the plan one at a time for approval:
   - Overview and goals
   - Files to create
   - Files to modify (with line numbers)
   - Component architecture
   - State management approach
   - API/data requirements
   - Testing strategy
   - **Detailed implementation steps** with code examples
   - Potential issues and mitigations
   - Open questions that need decisions
4. Builds the plan incrementally based on your feedback
5. Saves as `{feature_name}_plan.md`

**Benefits:**
- Think through large features before writing code
- Get architectural guidance based on your existing patterns
- Identify potential issues early
- Create actionable implementation roadmap with specific steps
- Document decisions for team review
- Iterate on the plan before committing to code

**Perfect for:**
- Complex new features
- Cross-cutting changes affecting multiple files
- Features requiring architectural decisions
- Team collaboration (creates shareable implementation plan)
- Onboarding new developers to a feature

## Uninstalling

To remove dotfile symlinks:
```bash
cd ~/dotfiles
stow -D bin claude ghostty nvim tmux yazi zsh
```

This removes the symlinks but keeps your dotfiles directory intact.
