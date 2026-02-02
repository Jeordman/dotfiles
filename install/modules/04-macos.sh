#!/usr/bin/env bash
# 04-macos.sh - macOS-specific keyboard settings

set -e

# Source libraries if not already loaded (allows standalone execution)
if ! type log_info &> /dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "$SCRIPT_DIR/lib/core.sh"
    source "$SCRIPT_DIR/lib/package-managers.sh"
fi

log_step "macOS Keyboard Settings"

# Only run on macOS
if [[ "$OS_TYPE" != "macos" ]]; then
    log_info "Skipping macOS settings (not on macOS)"
    exit 0
fi

log_step "Configuring keyboard repeat settings"

# Fast key repeat rate
defaults write NSGlobalDomain KeyRepeat -int 1
log_success "Key repeat rate set to 1"

# Short delay until key repeat
defaults write NSGlobalDomain InitialKeyRepeat -int 10
log_success "Initial key repeat delay set to 10"

log_success "macOS keyboard settings configured successfully!"