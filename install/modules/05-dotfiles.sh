#!/usr/bin/env bash

# 05-dotfiles.sh - Dotfiles linking with GNU Stow
# Creates backups and symlinks dotfiles to home directory

# Source libraries if not already loaded (allows standalone execution)
if ! type log_info &> /dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "$SCRIPT_DIR/lib/core.sh"
    source "$SCRIPT_DIR/lib/package-managers.sh"
fi

log_step "Linking Dotfiles with GNU Stow"

cd "$DOTFILES_DIR" || {
    log_error "Could not change to dotfiles directory: $DOTFILES_DIR"
    exit 1
}

# Backup existing configs if they exist and aren't symlinks
backup_if_exists() {
    local file=$1
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d_%H%M%S)

    if [ -f "$file" ] && [ ! -L "$file" ]; then
        log_info "Backing up existing $file to ${file}.backup.$backup_timestamp"
        mv "$file" "${file}.backup.$backup_timestamp"
    fi

    if [ -d "$file" ] && [ ! -L "$file" ]; then
        log_info "Backing up existing $file to ${file}.backup.$backup_timestamp"
        mv "$file" "${file}.backup.$backup_timestamp"
    fi
}

# Backup existing configurations
log_info "Checking for existing configurations..."
backup_if_exists "$HOME/.zshrc"
backup_if_exists "$HOME/.zprofile"
backup_if_exists "$HOME/.tmux.conf"
backup_if_exists "$HOME/.gitconfig"
backup_if_exists "$HOME/.config/nvim"
backup_if_exists "$HOME/.codex/config.toml"
backup_if_exists "$HOME/.codex/AGENTS.md"
backup_if_exists "$HOME/.config/ghostty"
backup_if_exists "$HOME/.config/btop"
backup_if_exists "$HOME/.config/herdr/config.toml"

# Stow all configurations
# Using -R (restow) to handle existing symlinks gracefully
log_info "Creating symlinks with GNU Stow..."

# ghostty is a GUI terminal emulator and herdr is a macOS-only binary whose config
# hardcodes /Users paths — both are client-side tools. On a headless Linux box
# (e.g. the home server) their configs are dead weight at best and quietly
# misleading at worst, so they're excluded there.
#
# lazygit ships its config under ~/Library/Application Support (the macOS path);
# the Linux equivalent is linked separately below.
#
# codex is macOS-only for the same reason as herdr: config.toml is rewritten by
# codex itself and carries machine-specific state (a /Applications/ChatGPT.app
# MCP server with a 120s startup timeout, absolute CODEX_HOME, per-project trust
# entries keyed by /Users paths). Its portable half, AGENTS.md, is linked below.
STOW_PACKAGES=(bin btop claude git hunk nvim tmux yazi zsh)
if [[ "$OS_TYPE" == "macos" ]]; then
    STOW_PACKAGES+=(ghostty herdr codex lazygit)
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would run: stow -R -v ${STOW_PACKAGES[*]}"
else
    # Check which directories exist before stowing
    # Not `local` — this block runs at top level when the module is executed
    # standalone (see the source guard at the top of the file).
    stow_targets=()

    for dir in "${STOW_PACKAGES[@]}"; do
        if [ -d "$DOTFILES_DIR/$dir" ]; then
            stow_targets+=("$dir")
        else
            log_warning "Directory $dir not found, skipping"
        fi
    done

    if [ ${#stow_targets[@]} -eq 0 ]; then
        log_error "No dotfile directories found to stow"
        exit 1
    fi

    # Run stow with restow flag (-R) for idempotency
    if stow -R -v "${stow_targets[@]}" 2>&1; then
        log_success "Dotfiles linked successfully"
        log_info "Linked: ${stow_targets[*]}"
    else
        log_error "Failed to link dotfiles with stow"
        log_info "You can try manually: cd $DOTFILES_DIR && stow -R ${stow_targets[*]}"
        exit 1
    fi
fi

# Share curated Claude config with the per-directory "personal" account.
# ~/.claude-personal is the config dir used when CLAUDE_CONFIG_DIR points at it
# (see ~/personal/.envrc and docs/direnv.md). It reuses the SAME dotfiles sources
# as ~/.claude, so both accounts share skills/commands/hooks/scripts/settings/
# statusline. Login and MCP servers stay separate per account by design.
link_personal_claude_config() {
    local src="$DOTFILES_DIR/claude/.claude"
    local dst="$HOME/.claude-personal"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would link shared Claude config into $dst"
        return 0
    fi

    mkdir -p "$dst"

    local item backup_timestamp
    for item in skills commands hooks scripts settings.json statusline-command.sh; do
        # Back up a real (non-symlink) file/dir that would collide
        if [ -e "$dst/$item" ] && [ ! -L "$dst/$item" ]; then
            backup_timestamp=$(date +%Y%m%d_%H%M%S)
            mv "$dst/$item" "$dst/$item.backup.$backup_timestamp"
        fi
        ln -sfn "$src/$item" "$dst/$item"
    done

    # agents are local (not in dotfiles) — share the main account's set if present
    if [ -d "$HOME/.claude/agents" ]; then
        ln -sfn "$HOME/.claude/agents" "$dst/agents"
    fi

    log_success "Shared Claude config linked into ~/.claude-personal (personal account)"
}

link_personal_claude_config

# Linux equivalents for the two packages stow skips there.
#
# lazygit: the repo holds one copy of config.yml at the macOS location
# (~/Library/Application Support/lazygit). Linux lazygit reads
# ~/.config/lazygit/config.yml instead, so point that at the same file rather
# than duplicating it — a second copy would silently drift.
#
# codex: config.toml is machine-specific and skipped, but ~/.codex/AGENTS.md is
# the global instruction file and is fully portable.
link_linux_only_configs() {
    [[ "$OS_TYPE" == "macos" ]] && return 0

    local lazygit_src="$DOTFILES_DIR/lazygit/Library/Application Support/lazygit/config.yml"
    local codex_src="$DOTFILES_DIR/codex/.codex/AGENTS.md"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would link ~/.config/lazygit/config.yml and ~/.codex/AGENTS.md"
        return 0
    fi

    if [ -f "$lazygit_src" ]; then
        mkdir -p "$HOME/.config/lazygit"
        backup_if_exists "$HOME/.config/lazygit/config.yml"
        ln -sfn "$lazygit_src" "$HOME/.config/lazygit/config.yml"
        log_success "Linked lazygit config into ~/.config/lazygit (Linux path)"
    fi

    if [ -f "$codex_src" ]; then
        mkdir -p "$HOME/.codex"
        backup_if_exists "$HOME/.codex/AGENTS.md"
        ln -sfn "$codex_src" "$HOME/.codex/AGENTS.md"
        log_success "Linked ~/.codex/AGENTS.md (config.toml stays machine-local on Linux)"
    fi
}

link_linux_only_configs

# Create .p10k.zsh if it doesn't exist (Powerlevel10k config)
if [ ! -f "$HOME/.p10k.zsh" ] && [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
    log_info "Powerlevel10k theme installed but no .p10k.zsh found"
    log_info "Run 'p10k configure' after opening zsh to set up your prompt"
fi

# Register Codex as an MCP server for Claude Code (user scope, idempotent)
if command -v claude &> /dev/null && command -v codex &> /dev/null; then
    if claude mcp get codex &> /dev/null; then
        log_info "Codex MCP server already registered with Claude Code"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would register codex as MCP server: claude mcp add -s user codex codex mcp-server"
    else
        log_info "Registering codex as MCP server for Claude Code..."
        if claude mcp add -s user codex codex mcp-server &> /dev/null; then
            log_success "Codex MCP server registered (user scope)"
        else
            log_warning "Failed to register codex MCP server — run manually: claude mcp add -s user codex codex mcp-server"
        fi
    fi
elif command -v claude &> /dev/null; then
    log_warning "Claude Code installed but codex CLI missing — install codex, then run: claude mcp add -s user codex codex mcp-server"
fi

# Remind about manual setup steps
if [ ! -f "$HOME/.gitconfig.local" ]; then
    log_warning "Missing ~/.gitconfig.local — git commits won't have your name/email"
    log_info "Create it with:"
    log_info "  printf '[user]\n\tname = Your Name\n\temail = you@example.com\n' > ~/.gitconfig.local"
fi

if command -v gh &> /dev/null && ! gh auth status &> /dev/null; then
    log_warning "GitHub CLI is not authenticated"
    log_info "Run: gh auth login"
fi

log_success "Dotfiles setup complete"
