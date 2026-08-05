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

# Must be initialised before use: the installer runs under `set -u`, so the
# check at the end of this file dies with "unbound variable" if stow succeeded
# and nothing ever assigned it.
STOW_FAILED=false

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
# Claude Code writes this itself on first launch (theme/tui prefs), so on any
# machine where Claude ran before install.sh it collides with the stowed copy.
backup_if_exists "$HOME/.claude/settings.json"

# The list above is inherently incomplete — any tool that writes its own config
# before install.sh runs creates a fresh collision. That matters more than it
# sounds: stow is ALL-OR-NOTHING. A single conflicting file aborts every package
# in the same invocation, so one stray ~/.claude/settings.json silently leaves
# nvim, zsh, tmux and the rest unlinked. Ask stow what would collide, back those
# targets up, and let the real run proceed.
resolve_stow_conflicts() {
    local -a packages=("$@")
    local -a conflicts=()
    local dry_output target

    dry_output=$(stow -R -n -v "${packages[@]}" 2>&1) && return 0

    # stow reports conflicts as:
    #   * cannot stow <src> over existing target <target> since neither a link nor a directory
    #   * existing target is neither a link nor a directory: <target>
    #   * existing target is not owned by stow: <target>
    while IFS= read -r target; do
        [ -n "$target" ] && conflicts+=("$target")
    done < <(printf '%s\n' "$dry_output" | sed -n \
        -e 's/.*over existing target \(.*\) since .*/\1/p' \
        -e 's/.*existing target is neither a link nor a directory: \(.*\)/\1/p' \
        -e 's/.*existing target is not owned by stow: \(.*\)/\1/p')

    if [ ${#conflicts[@]} -eq 0 ]; then
        # Dry run failed for a reason we can't auto-resolve — surface it.
        log_warning "stow reported a problem that could not be auto-resolved:"
        printf '%s\n' "$dry_output" | sed 's/^/    /'
        return 1
    fi

    log_warning "Found ${#conflicts[@]} conflicting target(s); backing them up"
    for target in "${conflicts[@]}"; do
        backup_if_exists "$HOME/$target"
    done
}

# Stow all configurations
# Using -R (restow) to handle existing symlinks gracefully
log_info "Creating symlinks with GNU Stow..."

# ghostty is a GUI terminal emulator, so its config is dead weight on a headless
# Linux box — you run Ghostty on the client and SSH in. It stays macOS-only.
#
# herdr used to be excluded here too, on the grounds that it was a macOS-only
# binary with /Users paths in its config. That stopped being true: herdr runs on
# the Linux server, and the one hardcoded path (the prefix+a agent picker) is now
# resolved via PATH instead. Excluding it meant the keybindings never linked —
# and worse, backup_if_exists below still moved ~/.config/herdr/config.toml aside
# on every run without linking a replacement, so herdr silently fell back to
# defaults and lost the config each time.
#
# lazygit ships its config under ~/Library/Application Support (the macOS path);
# the Linux equivalent is linked separately below.
#
# codex is macOS-only for the same reason as herdr: config.toml is rewritten by
# codex itself and carries machine-specific state (a /Applications/ChatGPT.app
# MCP server with a 120s startup timeout, absolute CODEX_HOME, per-project trust
# entries keyed by /Users paths). Its portable half, AGENTS.md, is linked below.
STOW_PACKAGES=(bin btop claude git herdr hunk nvim tmux tuicr yazi zsh)
if [[ "$OS_TYPE" == "macos" ]]; then
    STOW_PACKAGES+=(ghostty codex lazygit)
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would run: stow -R -v ${STOW_PACKAGES[*]}"

    # Actually ask stow what would happen. A dry run that only prints the
    # command it would have run is useless for the one question you want
    # answered before touching a working machine: "will this move any of my
    # files?" `stow -n` changes nothing, so this is safe to run here.
    dry_targets=()
    for dir in "${STOW_PACKAGES[@]}"; do
        [ -d "$DOTFILES_DIR/$dir" ] && dry_targets+=("$dir")
    done

    if [ ${#dry_targets[@]} -gt 0 ]; then
        if stow_preview=$(stow -R -n -v "${dry_targets[@]}" 2>&1); then
            log_success "[DRY RUN] No conflicts — nothing would be backed up"
        else
            log_warning "[DRY RUN] stow reports conflicts; these would be backed up first:"
            printf '%s\n' "$stow_preview" | sed -n \
                -e 's/.*over existing target \(.*\) since .*/    ~\/\1/p' \
                -e 's/.*existing target is neither a link nor a directory: \(.*\)/    ~\/\1/p' \
                -e 's/.*existing target is not owned by stow: \(.*\)/    ~\/\1/p'
            log_info "Each would be moved to <file>.backup.<timestamp> — nothing is deleted"
        fi
    fi
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

    # Clear anything that would make stow abort the whole batch.
    # `|| true` is required: this runs under `set -euo pipefail`, and the
    # function returns non-zero when it sees a stow problem it can't auto-fix.
    # Without the guard that advisory failure would kill the entire install.
    resolve_stow_conflicts "${stow_targets[@]}" || true

    # Run stow with restow flag (-R) for idempotency
    if stow -R -v "${stow_targets[@]}" 2>&1; then
        log_success "Dotfiles linked successfully"
        log_info "Linked: ${stow_targets[*]}"
    else
        # Don't exit — the steps below (personal Claude config, Linux-only
        # links, Codex MCP registration) are independent of stow and were
        # previously skipped entirely whenever one package conflicted.
        log_error "Failed to link dotfiles with stow — NO packages were linked"
        log_error "stow is all-or-nothing: fix the conflict above and re-run"
        log_info "You can try manually: cd $DOTFILES_DIR && stow -R ${stow_targets[*]}"
        STOW_FAILED=true
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

# Powerlevel10k prompt config.
#
# ~/.p10k.zsh is generated by `p10k configure` and is pure configuration, so it
# belongs in the repo — otherwise every new machine gets a default prompt and you
# re-answer the wizard. If it's tracked (zsh/.p10k.zsh), stow links it like any
# other file and there's nothing to do here.
if [ -f "$DOTFILES_DIR/zsh/.p10k.zsh" ]; then
    log_success "Powerlevel10k config linked from dotfiles"
elif [ -f "$HOME/.p10k.zsh" ]; then
    # Configured on this machine but never committed — it'll be lost on the next
    # box. Tell the user how to carry it across.
    log_warning "~/.p10k.zsh exists but isn't tracked in dotfiles"
    log_info "Keep your prompt across machines with:"
    log_info "  mv ~/.p10k.zsh $DOTFILES_DIR/zsh/.p10k.zsh && cd $DOTFILES_DIR && stow -R zsh"
elif [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
    log_info "Powerlevel10k theme installed but no .p10k.zsh found"
    log_info "Run 'p10k configure' in zsh, then move the result into the repo:"
    log_info "  mv ~/.p10k.zsh $DOTFILES_DIR/zsh/.p10k.zsh && cd $DOTFILES_DIR && stow -R zsh"
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

if [[ "$STOW_FAILED" == "true" ]]; then
    log_error "Dotfiles setup finished WITH ERRORS — symlinks were not created"
    exit 1
fi

log_success "Dotfiles setup complete"
