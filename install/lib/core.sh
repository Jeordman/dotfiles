#!/usr/bin/env bash

# core.sh - Core utilities for dotfiles installation
# Provides logging, error handling, OS detection, and user interaction

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_step() {
    echo ""
    echo -e "${CYAN}==>${NC} ${MAGENTA}$*${NC}"
    echo "--------------------------------"
}

# Optional-package bookkeeping
#
# Not every tool exists in every OS's repos (yazi and lazygit aren't in apt, for
# example). With `set -euo pipefail` a single missing package used to abort the
# whole run, so everything after it — oh-my-zsh, p10k, stow — silently
# never happened. Failures are collected here instead and reported at the end.
FAILED_PACKAGES=()

record_failed_package() {
    FAILED_PACKAGES+=("$1")
}

report_failed_packages() {
    if [ ${#FAILED_PACKAGES[@]} -eq 0 ]; then
        return 0
    fi

    echo ""
    log_warning "Not installed (unavailable via $PACKAGE_MANAGER):"
    local pkg
    for pkg in "${FAILED_PACKAGES[@]}"; do
        echo "    - $pkg"
    done
    log_info "Everything else completed. Install these by hand if you need them."
}

# Error handling
handle_error() {
    local exit_code=$1
    local line_number=$2

    log_error "Installation failed at line $line_number (exit code: $exit_code)"
    log_error "Check the output above for details"
    log_info "You can re-run this script - it's safe to run multiple times"

    exit "$exit_code"
}

trap 'handle_error $? $LINENO' ERR

# OS Detection
detect_os() {
    local OS
    OS="$(uname -s)"

    case "$OS" in
        Darwin)
            log_info "Detected macOS ($(sw_vers -productVersion))"
            export OS_TYPE="macos"
            export PACKAGE_MANAGER="brew"
            ;;
        Linux)
            log_info "Detected Linux"
            export OS_TYPE="linux"
            detect_linux_package_manager
            ;;
        *)
            log_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
}

detect_linux_package_manager() {
    if command -v apt-get &> /dev/null; then
        export PACKAGE_MANAGER="apt"
        log_info "Using package manager: apt"
    elif command -v dnf &> /dev/null; then
        export PACKAGE_MANAGER="dnf"
        log_info "Using package manager: dnf"
    elif command -v pacman &> /dev/null; then
        export PACKAGE_MANAGER="pacman"
        log_info "Using package manager: pacman"
    elif command -v zypper &> /dev/null; then
        export PACKAGE_MANAGER="zypper"
        log_info "Using package manager: zypper"
    else
        log_error "No supported package manager found"
        log_info "Supported: apt, dnf, pacman, zypper"
        exit 1
    fi
}

# User interaction
ask_yes_no() {
    local prompt=$1
    local default=${2:-"y"}

    # Non-interactive mode always returns true
    if [[ "${NON_INTERACTIVE:-}" == "1" ]]; then
        return 0
    fi

    local yn_prompt="[Y/n]"
    [[ "$default" == "n" ]] && yn_prompt="[y/N]"

    local response
    read -r -p "$prompt $yn_prompt " response

    response=${response:-$default}

    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Header
print_header() {
    echo ""
    echo "======================================"
    echo "  Dotfiles Installation Script"
    echo "======================================"
    echo ""
}

# The user's LOGIN shell, portably.
#
# Do NOT use $SHELL for this: it's inherited from whatever launched install.sh
# and does not change when chsh succeeds, so it can't tell you whether the
# switch worked.
#
# `getent` is glibc — it does not exist on macOS, where accounts live in
# Directory Services and `dscl` is authoritative (/etc/passwd holds only system
# accounts there). Falling back to $SHELL keeps callers safe on either OS.
get_login_shell() {
    local shell=""

    if command -v getent &> /dev/null; then
        shell=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)
    elif command -v dscl &> /dev/null; then
        shell=$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')
    fi

    if [[ -z "$shell" ]]; then
        shell=$(awk -F: -v u="$USER" '$1 == u { print $7 }' /etc/passwd 2>/dev/null)
    fi

    echo "${shell:-$SHELL}"
}

# Completion message
print_completion_message() {
    echo ""
    echo "======================================"
    echo "  Installation Complete!"
    echo "======================================"
    echo ""
    local login_shell
    login_shell=$(get_login_shell)

    echo "Next steps:"
    if [[ "$login_shell" == *zsh ]]; then
        echo "1. Restart your terminal, or reload with: exec zsh"
    else
        # Don't suggest `source ~/.zshrc` here: from bash that fails loudly with
        # "bad substitution" and "autoload: command not found", because zsh
        # syntax isn't valid bash. `exec zsh` is what actually works.
        echo "1. Start zsh with: exec zsh"
        echo "   (your login shell is $login_shell, which this repo does not"
        echo "    configure — zsh holds all the aliases and functions)"
    fi

    if command -v zsh &> /dev/null && [[ "$login_shell" != *zsh ]]; then
        echo "2. Default shell is NOT zsh yet. chsh needs your password, so it"
        echo "   fails in unattended installs and when the account is SSH-key"
        echo "   only. Switch it with either of:"
        echo "     chsh -s $(command -v zsh)"
        echo "     sudo chsh -s $(command -v zsh) $USER   # if the above fails"
    else
        echo "2. Default shell is zsh"
    fi
    echo "3. Open neovim - plugins will auto-install on first run"
    echo "4. Run :checkhealth in neovim to verify setup"
    echo ""
    echo "Configuration files are symlinked from:"
    echo "  $DOTFILES_DIR"
    echo ""
    echo "To uninstall, run:"
    if [[ "${OS_TYPE:-}" == "macos" ]]; then
        echo "  cd $DOTFILES_DIR && stow -D nvim zsh ghostty"
    else
        echo "  cd $DOTFILES_DIR && stow -D nvim zsh"
    fi
    echo ""
}
