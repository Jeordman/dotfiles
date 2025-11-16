#!/usr/bin/env bash

# 01-system.sh - Core system tools installation
# Installs essential system utilities needed for development

log_step "Installing Core System Tools"

# GNU Stow (for managing dotfiles)
ensure_package "stow" "stow" "GNU Stow"

# Git
ensure_package "git" "git" "Git"

# Curl (should already be installed, but check anyway)
ensure_package "curl" "curl" "curl"

# Build essentials (Linux only)
if [[ "$OS_TYPE" == "linux" ]]; then
    case "$PACKAGE_MANAGER" in
        apt)
            if ! dpkg -l | grep -q build-essential; then
                install_package "build-essential" "Build Essential"
            else
                log_success "Build Essential already installed"
            fi
            ;;
        dnf)
            if ! rpm -q gcc &> /dev/null; then
                install_package "gcc" "GCC"
                install_package "make" "Make"
            else
                log_success "Build tools already installed"
            fi
            ;;
        pacman)
            if ! pacman -Q base-devel &> /dev/null; then
                install_package "base-devel" "Base Development Tools"
            else
                log_success "Base development tools already installed"
            fi
            ;;
    esac
fi

log_success "Core system tools installation complete"
