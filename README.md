# Dotfiles

Personal development environment configuration with automated installation.

## Quick Start

### 1. Clone the Repository

```bash
cd ~
git clone --recurse-submodules <your-dotfiles-repo-url> dotfiles
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
- Supports: nvim, tmux, zsh, ghostty

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

# Or link everything at once
stow nvim tmux zsh ghostty
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

## Submodules

Nvim config is a submodule → [kickstart.nvim](https://github.com/Jeordman/kickstart.nvim)

**Initialize/update submodules** (if you cloned without `--recurse-submodules`):
```bash
git submodule update --init --recursive
```

**Work on nvim config**:
```bash
cd nvim/.config/nvim
git checkout main
# make changes...
git add . && git commit -m "msg" && git push
cd ~/dotfiles
git add nvim/.config/nvim && git commit -m "Update nvim"
```

## Uninstalling

To remove dotfile symlinks:
```bash
cd ~/dotfiles
stow -D nvim tmux zsh ghostty
```

This removes the symlinks but keeps your dotfiles directory intact.
