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
- Supports: bin, claude, ghostty, nvim, tmux, yazi, zsh

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
stow bin claude ghostty nvim tmux yazi zsh
```

## Post-Installation

1. **Restart your terminal** or run:
   ```bash
   source ~/.zshrc
   ```

2. **Set zsh as default shell** (if not done automatically):
   ```bash
   chsh -s $(which zsh)
   ```

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

### `/worktree-init` - Create feature branch with worktree and tmux session

Initialize a new git worktree with a feature branch and tmux session for parallel development.

**Usage:**
```bash
/worktree-init <project> <base-branch> <type> <ticket> <description>
```

**Example:**
```bash
/worktree-init ClimbSmarter main feat ECOM-1234 checkout-flow
```

**What it does:**
1. Creates a feature branch: `feat/ECOM-1234-checkout-flow`
2. Creates a git worktree as a sibling directory
3. Copies `.env` and `.env.local` files
4. Initializes a tmux session for the worktree
5. Attaches you to the new tmux session

### `/worktree-remove` - Safely remove worktrees

Remove one or more worktrees, but only if code is committed and pushed.

**Usage:**
```bash
/worktree-remove <name-or-all>
```

**Examples:**
```bash
/worktree-remove all                                    # Remove all clean worktrees
/worktree-remove ClimbSmarter-feat-ECOM-1234-checkout  # Remove specific worktree
```

**Safety checks:**
- Prevents deletion of worktrees with uncommitted changes
- Prevents deletion of worktrees with unpushed commits
- Kills associated tmux sessions automatically
- Protects main repository from accidental deletion

## Uninstalling

To remove dotfile symlinks:
```bash
cd ~/dotfiles
stow -D bin claude ghostty nvim tmux yazi zsh
```

This removes the symlinks but keeps your dotfiles directory intact.
