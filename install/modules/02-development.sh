#!/usr/bin/env bash

# 02-development.sh - Development tools installation
# Installs core development tools and utilities

log_step "Installing Development Tools"

# Neovim
ensure_package "nvim" "neovim" "Neovim"

# Ripgrep (used by Telescope in neovim)
ensure_package "rg" "ripgrep" "ripgrep"

# fzf (fuzzy finder)
ensure_package "fzf" "fzf" "fzf"

# fd (fast find alternative, used by Telescope)
if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    ensure_package "fd" "fd-find" "fd"
else
    ensure_package "fd" "fd" "fd"
fi

# lazygit (git UI in neovim)
ensure_package "lazygit" "lazygit" "lazygit"

# jq (JSON processor)
ensure_package "jq" "jq" "jq"

# GitHub CLI
if [[ "$OS_TYPE" == "macos" ]]; then
    ensure_package "gh" "gh" "GitHub CLI"
else
    # Install gh on Linux
    if ! command -v gh &> /dev/null; then
        case "$PACKAGE_MANAGER" in
            apt)
                log_info "Installing GitHub CLI..."
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                sudo apt update
                install_package "gh" "GitHub CLI"
                ;;
            dnf)
                sudo dnf install 'dnf-command(config-manager)'
                sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
                install_package "gh" "GitHub CLI"
                ;;
            *)
                log_warning "GitHub CLI installation not automated for this package manager"
                log_info "Install manually from: https://github.com/cli/cli#installation"
                ;;
        esac
    else
        log_success "GitHub CLI already installed"
    fi
fi

log_success "Development tools installation complete"
