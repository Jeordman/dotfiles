#!/usr/bin/env bash

# 05-dotfiles.sh - Dotfiles linking with GNU Stow
# Creates backups and symlinks dotfiles to home directory

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
backup_if_exists "$HOME/.tmux.conf"
backup_if_exists "$HOME/.config/nvim"
backup_if_exists "$HOME/.config/ghostty"

# Stow all configurations
# Using -R (restow) to handle existing symlinks gracefully
log_info "Creating symlinks with GNU Stow..."

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would run: stow -R -v bin claude ghostty nvim tmux yazi zsh"
else
    # Check which directories exist before stowing
    local stow_targets=()

    for dir in bin claude ghostty nvim tmux yazi zsh; do
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

# Create .p10k.zsh if it doesn't exist (Powerlevel10k config)
if [ ! -f "$HOME/.p10k.zsh" ] && [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
    log_info "Powerlevel10k theme installed but no .p10k.zsh found"
    log_info "Run 'p10k configure' after opening zsh to set up your prompt"
fi

log_success "Dotfiles setup complete"
