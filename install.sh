#!/usr/bin/env bash

#==============================================================================
# Dotfiles Installation Script
#==============================================================================
# Usage:
#   ./install.sh              # Interactive mode
#   ./install.sh --all        # Install everything
#   ./install.sh --minimal    # Core tools only
#   ./install.sh --dry-run    # Preview without installing
#
# Environment variables:
#   NON_INTERACTIVE=1         # Skip prompts
#==============================================================================

set -euo pipefail

# Script directory
readonly DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="$DOTFILES_DIR/install/lib"
readonly MODULES_DIR="$DOTFILES_DIR/install/modules"

# Export for use in modules
export DOTFILES_DIR
export DRY_RUN=false

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --all         Install all tools and applications
    --minimal     Install only core development tools
    --dry-run     Preview installation without making changes
    --help, -h    Show this help message

Environment Variables:
    NON_INTERACTIVE=1    Skip all prompts (use with --all or --minimal)

Examples:
    $0                          # Interactive mode with prompts
    $0 --all                    # Install everything
    $0 --minimal                # Core tools only
    $0 --dry-run --all          # Preview full installation
    NON_INTERACTIVE=1 $0 --all  # Fully automated installation

EOF
}

# Source library functions
source "$LIB_DIR/core.sh"
source "$LIB_DIR/package-managers.sh"
source "$LIB_DIR/validation.sh"

# Parse command line arguments
MODE="interactive"

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            MODE="all"
            shift
            ;;
        --minimal)
            MODE="minimal"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            export DRY_RUN
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Run a module
run_module() {
    local module=$1
    local module_path="$MODULES_DIR/$module"

    if [[ -f "$module_path" ]]; then
        log_info "Running module: $module"
        source "$module_path"
    else
        log_warning "Module not found: $module"
    fi
}

# Interactive installation
run_interactive_installation() {
    log_info "Interactive installation mode"
    echo ""

    if ask_yes_no "Install core system tools?"; then
        run_module "01-system.sh"
    fi

    if ask_yes_no "Install development tools (neovim, git, ripgrep, etc.)?"; then
        run_module "02-development.sh"
    fi

    if ask_yes_no "Install terminal enhancements (zsh, tmux, modern CLI tools)?"; then
        run_module "03-terminal.sh"
    fi

    if ask_yes_no "Link dotfiles using GNU Stow?"; then
        run_module "05-dotfiles.sh"
    fi
}

# Main installation flow
main() {
    print_header

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    # Detect OS first (needed for other checks)
    detect_os

    # Pre-flight checks
    check_requirements
    setup_package_manager

    # Run installation modules
    if [[ "$MODE" == "all" ]]; then
        run_module "01-system.sh"
        run_module "02-development.sh"
        run_module "03-terminal.sh"
        run_module "05-dotfiles.sh"

    elif [[ "$MODE" == "minimal" ]]; then
        run_module "01-system.sh"
        run_module "02-development.sh"
        run_module "05-dotfiles.sh"

    else
        # Interactive mode
        run_interactive_installation
    fi

    # Verify installation (optional)
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_installation
    fi

    print_completion_message
}

# Run main function
main "$@"
