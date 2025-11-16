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

# Completion message
print_completion_message() {
    echo ""
    echo "======================================"
    echo "  Installation Complete!"
    echo "======================================"
    echo ""
    echo "Next steps:"
    echo "1. Restart your terminal or run: source ~/.zshrc"
    if command -v zsh &> /dev/null && [[ "$SHELL" != "$(which zsh)" ]]; then
        echo "2. Your default shell has been changed to zsh"
    fi
    echo "3. Open tmux and press Ctrl-Space + I to install plugins"
    echo "4. Open neovim - plugins will auto-install on first run"
    echo "5. Run :checkhealth in neovim to verify setup"
    echo ""
    echo "Configuration files are symlinked from:"
    echo "  $DOTFILES_DIR"
    echo ""
    echo "To uninstall, run:"
    echo "  cd $DOTFILES_DIR && stow -D nvim tmux zsh ghostty"
    echo ""
}
