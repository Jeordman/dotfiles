#!/usr/bin/env bash

# validation.sh - Pre-flight checks and system validation
# Ensures the system meets requirements before installation

check_requirements() {
    log_step "Running pre-flight checks"

    local all_checks_passed=true

    # Check for internet connectivity
    if ! check_internet; then
        log_error "No internet connection detected"
        all_checks_passed=false
    else
        log_success "Internet connection verified"
    fi

    # Check for curl
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed - required for installation"
        all_checks_passed=false
    else
        log_success "curl is available"
    fi

    # Check for git
    if ! command -v git &> /dev/null; then
        log_warning "git is not installed - will be installed during setup"
    else
        log_success "git is available"
    fi

    # Check disk space (require at least 1GB free)
    if ! check_disk_space; then
        log_warning "Low disk space detected - installation may fail"
    else
        log_success "Sufficient disk space available"
    fi

    if [[ "$all_checks_passed" == "false" ]]; then
        log_error "Pre-flight checks failed - please resolve issues above"
        exit 1
    fi

    log_success "All pre-flight checks passed"
}

check_internet() {
    # Try to connect to GitHub (used for many installations)
    if curl -s --connect-timeout 5 https://github.com &> /dev/null; then
        return 0
    fi
    return 1
}

check_disk_space() {
    local available_kb

    if [[ "$OS_TYPE" == "macos" ]]; then
        available_kb=$(df -k / | awk 'NR==2 {print $4}')
    else
        available_kb=$(df -k / | awk 'NR==2 {print $4}')
    fi

    # Require at least 1GB (1048576 KB)
    if [[ "$available_kb" -gt 1048576 ]]; then
        return 0
    fi
    return 1
}

# Verify installation was successful
verify_installation() {
    log_step "Verifying installation"

    local verification_failed=false

    # Check core tools
    local -a core_tools=("stow" "git" "nvim" "tmux" "zsh")

    for tool in "${core_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "$tool is available"
        else
            log_warning "$tool is not available"
            verification_failed=true
        fi
    done

    # Check if dotfiles are linked
    if [[ -L "$HOME/.zshrc" ]]; then
        log_success "Dotfiles are properly linked"
    else
        log_warning "Dotfiles may not be properly linked"
    fi

    if [[ "$verification_failed" == "true" ]]; then
        log_warning "Some verifications failed - you may need to troubleshoot"
    else
        log_success "All verifications passed"
    fi
}
