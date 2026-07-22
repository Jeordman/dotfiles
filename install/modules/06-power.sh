#!/usr/bin/env bash
# 06-power.sh - Always-on power settings for remote-access machines
#
# Keeps the Mac reachable while plugged in so a running Claude Code session
# stays alive for the Claude phone app: never system-sleeps on AC power, but
# still lets the display sleep. All settings are AC-only (`-c`), so battery
# behavior is untouched. Idempotent; honors --dry-run.

set -e

# Source libraries if not already loaded (allows standalone execution)
if ! type log_info &> /dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "$SCRIPT_DIR/lib/core.sh"
    source "$SCRIPT_DIR/lib/package-managers.sh"
fi

# Detect the OS when run standalone (install.sh normally does this first)
if [[ -z "${OS_TYPE:-}" ]]; then
    detect_os
fi

log_step "Power Management (always-on for remote access)"

# Only run on macOS
if [[ "$OS_TYPE" != "macos" ]]; then
    log_info "Skipping power settings (not on macOS)"
    exit 0
fi

# Run a privileged command, respecting DRY_RUN and avoiding a hang when
# sudo can't authenticate non-interactively.
run_priv() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: sudo $*"
        return 0
    fi
    if ! sudo -n true 2>/dev/null && [[ "${NON_INTERACTIVE:-}" == "1" ]]; then
        log_warning "Skipping 'sudo $*' - needs a password and running non-interactively"
        return 0
    fi
    sudo "$@"
}

# --- Never fully sleep on AC, but let the screen sleep ---
run_priv pmset -c sleep 0          && log_success "System sleep disabled on AC"
run_priv pmset -c disksleep 0      && log_success "Disk sleep disabled on AC"
run_priv pmset -c displaysleep 10  && log_success "Display sleeps after 10 min (panel still rests)"
run_priv pmset -c womp 1           && log_success "Wake-on-network enabled"
run_priv pmset -c powernap 1       && log_success "Power Nap enabled"

log_success "Power management configured"
log_info "Verify with: pmset -g custom"
log_info "Laptop note: closing the lid still forces sleep unless in clamshell mode (external display + power)."
