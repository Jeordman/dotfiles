#!/usr/bin/env bash

# 03-terminal.sh - Terminal and shell enhancement tools
# Installs zsh, oh-my-zsh, tmux, and modern CLI replacements

log_step "Installing Terminal Enhancements"

# Zsh
ensure_package "zsh" "zsh" "Zsh"

# Tmux
ensure_package "tmux" "tmux" "Tmux"

# Modern CLI tools
log_info "Installing modern CLI tools..."

# bat (better cat)
ensure_package "bat" "bat" "bat"

# eza (better ls)
if [[ "$OS_TYPE" == "macos" ]]; then
    ensure_package "eza" "eza" "eza"
else
    # eza may need to be installed from cargo on some Linux distros
    if ! command -v eza &> /dev/null; then
        case "$PACKAGE_MANAGER" in
            apt)
                # Check if cargo is available, otherwise install from package if available
                if command -v cargo &> /dev/null; then
                    log_info "Installing eza via cargo..."
                    cargo install eza
                else
                    log_warning "eza installation requires cargo - skipping"
                    log_info "Install rust/cargo first or use: apt install eza (if available)"
                fi
                ;;
            dnf|pacman)
                ensure_package "eza" "eza" "eza"
                ;;
            *)
                log_warning "eza installation not automated for this package manager"
                ;;
        esac
    else
        log_success "eza already installed"
    fi
fi

# zoxide (smart cd)
ensure_package "zoxide" "zoxide" "zoxide"

# delta (better git diff)
if [[ "$OS_TYPE" == "macos" ]]; then
    ensure_package "delta" "git-delta" "delta"
else
    ensure_package "delta" "git-delta" "delta"
fi

# thefuck (command correction tool)
ensure_package "thefuck" "thefuck" "thefuck"

# Node Version Manager (NVM)
log_info "Setting up NVM (Node Version Manager)..."
if [ ! -d "$HOME/.nvm" ]; then
    log_info "Installing NVM..."
    local nvm_version="v0.40.0"
    safe_curl_install "https://raw.githubusercontent.com/nvm-sh/nvm/$nvm_version/install.sh" "NVM"

    # Load NVM for current session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # Install latest LTS version of Node.js
    if command -v nvm &> /dev/null; then
        log_info "Installing Node.js LTS..."
        nvm install --lts
        nvm use --lts
        log_success "Node.js LTS installed"
    fi
else
    log_success "NVM already installed"
fi

# Oh My Zsh
log_info "Setting up Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_info "Installing Oh My Zsh..."
    safe_curl_install "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" "Oh My Zsh" "--unattended"
else
    log_success "Oh My Zsh already installed"
fi

# Zsh plugins
log_info "Installing Zsh plugins..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# zsh-autosuggestions
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    log_info "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    log_success "zsh-autosuggestions installed"
else
    log_success "zsh-autosuggestions already installed"
fi

# zsh-syntax-highlighting
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    log_info "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    log_success "zsh-syntax-highlighting installed"
else
    log_success "zsh-syntax-highlighting already installed"
fi

# Powerlevel10k theme
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    log_info "Installing Powerlevel10k theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
    log_success "Powerlevel10k installed"
else
    log_success "Powerlevel10k already installed"
fi

# Tmux Plugin Manager (TPM)
log_info "Setting up Tmux Plugin Manager..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    log_info "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    log_success "TPM installed"
else
    log_success "TPM already installed"
fi

# Change default shell to zsh
if command -v zsh &> /dev/null && [[ "$SHELL" != "$(which zsh)" ]]; then
    log_info "Changing default shell to zsh..."
    if chsh -s "$(which zsh)" 2>&1; then
        log_success "Default shell changed to zsh"
    else
        log_warning "Failed to change default shell - you may need to run: chsh -s \$(which zsh)"
    fi
else
    log_success "Default shell is already zsh"
fi

log_success "Terminal enhancements installation complete"
