#!/usr/bin/env bash

# package-managers.sh - Package manager abstraction layer
# Provides unified interface for installing packages across different systems

# Package manager setup
setup_package_manager() {
    if [[ "$OS_TYPE" == "macos" ]]; then
        setup_homebrew
    fi
}

setup_homebrew() {
    if command -v brew &> /dev/null; then
        log_success "Homebrew already installed"
        return 0
    fi

    log_step "Installing Homebrew"

    local brew_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    local temp_script

    temp_script=$(mktemp)

    if ! curl -fsSL "$brew_url" -o "$temp_script"; then
        log_error "Failed to download Homebrew installer"
        rm -f "$temp_script"
        return 1
    fi

    log_info "Running Homebrew installer..."
    /bin/bash "$temp_script"
    rm -f "$temp_script"

    # Add to PATH for current session
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    log_success "Homebrew installed successfully"
}

# Generic package installation
install_package() {
    local package=$1
    local display_name=${2:-$package}

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install: $display_name"
        return 0
    fi

    log_info "Installing $display_name..."

    case "$PACKAGE_MANAGER" in
        brew)
            if brew install "$package" 2>&1; then
                log_success "$display_name installed"
                return 0
            else
                log_warning "Failed to install $display_name"
                return 1
            fi
            ;;
        apt)
            if sudo apt-get install -y "$package" 2>&1; then
                log_success "$display_name installed"
                return 0
            else
                log_warning "Failed to install $display_name"
                return 1
            fi
            ;;
        dnf)
            if sudo dnf install -y "$package" 2>&1; then
                log_success "$display_name installed"
                return 0
            else
                log_warning "Failed to install $display_name"
                return 1
            fi
            ;;
        pacman)
            if sudo pacman -S --noconfirm "$package" 2>&1; then
                log_success "$display_name installed"
                return 0
            else
                log_warning "Failed to install $display_name"
                return 1
            fi
            ;;
        zypper)
            if sudo zypper install -y "$package" 2>&1; then
                log_success "$display_name installed"
                return 0
            else
                log_warning "Failed to install $display_name"
                return 1
            fi
            ;;
    esac
}

# Check if package is installed
is_package_installed() {
    local command_name=$1
    command -v "$command_name" &> /dev/null
}

# Install package if not already installed
ensure_package() {
    local command_name=$1
    local package_name=${2:-$command_name}
    local display_name=${3:-$package_name}

    if is_package_installed "$command_name"; then
        log_success "$display_name already installed"
        return 0
    fi

    install_package "$package_name" "$display_name"
}

# Install cask application (macOS only)
install_cask() {
    local cask_name=$1
    local display_name=${2:-$cask_name}

    if [[ "$OS_TYPE" != "macos" ]]; then
        log_warning "Cask installation only supported on macOS"
        return 1
    fi

    if brew list --cask "$cask_name" &> /dev/null 2>&1; then
        log_success "$display_name already installed"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install cask: $display_name"
        return 0
    fi

    log_info "Installing $display_name..."
    if brew install --cask "$cask_name" 2>&1; then
        log_success "$display_name installed"
        return 0
    else
        log_warning "Failed to install $display_name"
        return 1
    fi
}

# Download and execute installer script safely
safe_curl_install() {
    local url=$1
    local display_name=$2
    local args=${3:-}

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run installer from: $url"
        return 0
    fi

    local temp_script
    temp_script=$(mktemp)

    log_info "Downloading $display_name installer..."
    if ! curl -fsSL "$url" -o "$temp_script"; then
        log_error "Failed to download installer from $url"
        rm -f "$temp_script"
        return 1
    fi

    log_info "Running $display_name installer..."
    if bash "$temp_script" $args; then
        log_success "$display_name installed"
        rm -f "$temp_script"
        return 0
    else
        log_warning "Failed to install $display_name"
        rm -f "$temp_script"
        return 1
    fi
}
