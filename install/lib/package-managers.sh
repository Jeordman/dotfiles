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

    if install_package "$package_name" "$display_name"; then
        return 0
    fi

    # Deliberately non-fatal. Modules call this unguarded at top level, and the
    # installer runs under `set -e`, so returning non-zero here would kill the
    # entire run over one package that simply isn't in this distro's repos.
    record_failed_package "$display_name"
    return 0
}

# Debian and Ubuntu rename a couple of binaries to avoid clashing with older
# packages: bat ships as `batcat`, fd ships as `fdfind`. Symlink the expected
# name into ~/.local/bin, which .zshrc already has on PATH.
link_debian_binary_alias() {
    local expected=$1
    local actual=$2

    [[ "$PACKAGE_MANAGER" == "apt" ]] || return 0
    command -v "$expected" &> /dev/null && return 0
    command -v "$actual" &> /dev/null || return 0

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would link $expected -> $actual in ~/.local/bin"
        return 0
    fi

    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v "$actual")" "$HOME/.local/bin/$expected"
    log_success "Linked $expected -> $actual in ~/.local/bin"
}

# Extract a release archive, whichever format upstream chose. lazygit ships
# .tar.gz, yazi ships .zip — supporting only tar meant yazi could never be
# installed without a Rust toolchain.
#
# The zip branch degrades through three extractors so this works on a stock
# Ubuntu box: unzip isn't installed by default, but python3 always is.
extract_release_archive() {
    local file=$1
    local dest=$2

    case "$file" in
        *.tar.gz|*.tgz) tar -xzf "$file" -C "$dest" ;;
        *.tar.xz)       tar -xJf "$file" -C "$dest" ;;
        *.tar.bz2)      tar -xjf "$file" -C "$dest" ;;
        *.zip)
            if command -v unzip &> /dev/null; then
                unzip -q "$file" -d "$dest"
            elif command -v 7z &> /dev/null; then
                7z x -y -o"$dest" "$file" > /dev/null
            elif command -v python3 &> /dev/null; then
                python3 -m zipfile -e "$file" "$dest"
            else
                log_warning "No extractor available for .zip (need unzip, 7z or python3)"
                return 1
            fi
            ;;
        *)
            log_warning "Don't know how to extract: $file"
            return 1
            ;;
    esac
}

# Install one or more binaries from a GitHub release, for tools with no apt
# package (lazygit, yazi). Binaries land in ~/.local/bin, so no sudo is needed.
#
# Args: repo, binary, asset_pattern, [display_name], [extra binaries...]
# Extra binaries are companions shipped in the same archive (yazi's `ya` CLI);
# they're installed if present but never cause a failure.
install_from_github_release() {
    local repo=$1
    local binary=$2
    local asset_pattern=$3
    local display_name=${4:-$binary}
    local extra_binaries=("${@:5}")

    if command -v "$binary" &> /dev/null; then
        log_success "$display_name already installed"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install $display_name from github.com/$repo releases"
        return 0
    fi

    # -i (case-insensitive) matters: projects rename assets between releases
    # without warning. lazygit shipped "..._Linux_x86_64.tar.gz" for years and
    # switched to lowercase "..._linux_x86_64.tar.gz", which silently turned into
    # "Could not find a release asset" on every install until this was relaxed.
    local url
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | grep -oi "\"browser_download_url\": *\"[^\"]*${asset_pattern}[^\"]*\"" \
        | head -1 | cut -d'"' -f4) || true

    if [[ -z "$url" ]]; then
        log_warning "Could not find a $display_name release asset matching '$asset_pattern'"
        record_failed_package "$display_name"
        return 0
    fi

    local tmpdir asset
    tmpdir=$(mktemp -d)
    mkdir -p "$HOME/.local/bin"

    # Keep the upstream filename verbatim — extract_release_archive dispatches on
    # the extension, and a naive "${url##*.}" would turn "foo.tar.gz" into
    # "asset.gz", which matches no case branch and fails to extract.
    asset="$tmpdir/$(basename "$url")"

    if ! curl -fsSL "$url" -o "$asset"; then
        log_warning "Failed to download $display_name from $url"
        record_failed_package "$display_name"
        rm -rf "$tmpdir"
        return 0
    fi

    if ! extract_release_archive "$asset" "$tmpdir"; then
        log_warning "Failed to extract $display_name archive"
        record_failed_package "$display_name"
        rm -rf "$tmpdir"
        return 0
    fi

    # `find -exec` returns 0 even when it matches nothing, so the old code
    # reported success for an archive that didn't contain the binary. Locate it
    # explicitly and verify the install landed.
    local found name
    found=$(find "$tmpdir" -name "$binary" -type f -perm -u+x 2>/dev/null | head -1)

    if [[ -z "$found" ]]; then
        log_warning "$display_name archive did not contain an executable named '$binary'"
        record_failed_package "$display_name"
        rm -rf "$tmpdir"
        return 0
    fi

    if install -m 755 "$found" "$HOME/.local/bin/$binary" \
        && [[ -x "$HOME/.local/bin/$binary" ]]; then
        log_success "$display_name installed to ~/.local/bin"
    else
        log_warning "Failed to install $display_name to ~/.local/bin"
        record_failed_package "$display_name"
        rm -rf "$tmpdir"
        return 0
    fi

    # Companion binaries: best-effort, never fatal.
    for name in ${extra_binaries+"${extra_binaries[@]}"}; do
        found=$(find "$tmpdir" -name "$name" -type f -perm -u+x 2>/dev/null | head -1)
        if [[ -n "$found" ]]; then
            install -m 755 "$found" "$HOME/.local/bin/$name" \
                && log_success "$name installed to ~/.local/bin"
        fi
    done

    rm -rf "$tmpdir"
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

# npm-global CLIs
#
# ORDERING PROBLEM these solve: 02-development.sh runs before 03-terminal.sh,
# but nvm (and therefore npm) is installed by 03. On a fresh box every
# npm-backed tool was skipped with "needs npm, which isn't installed yet" and
# only appeared after a SECOND full run of install.sh.
#
# ensure_npm_global defers instead of giving up: if npm is missing it queues the
# package, and 03-terminal.sh calls flush_deferred_npm_globals once Node is
# available. Modules are sourced (not subprocesses), so the queue survives
# across them.
NPM_DEFERRED=()

ensure_npm_global() {
    local binary=$1
    local package=$2
    local display_name=${3:-$package}

    if command -v "$binary" &> /dev/null; then
        log_success "$display_name already installed"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run: npm install -g $package"
        return 0
    fi

    if ! command -v npm &> /dev/null; then
        log_info "Deferring $display_name until Node is installed"
        NPM_DEFERRED+=("$binary|$package|$display_name")
        return 0
    fi

    log_info "Installing $display_name..."
    if npm install -g "$package"; then
        log_success "$display_name installed"
    else
        log_warning "Failed to install $display_name"
        record_failed_package "$display_name"
    fi
}

# Retry everything ensure_npm_global queued. Safe to call when nothing is
# queued, and safe to call more than once.
flush_deferred_npm_globals() {
    [ ${#NPM_DEFERRED[@]} -eq 0 ] && return 0

    local entry binary package display_name
    local -a pending=("${NPM_DEFERRED[@]}")
    NPM_DEFERRED=()

    if ! command -v npm &> /dev/null; then
        log_warning "npm still unavailable — these need a manual install:"
        for entry in "${pending[@]}"; do
            IFS='|' read -r binary package display_name <<< "$entry"
            log_info "    npm install -g $package"
            record_failed_package "$display_name (needs npm)"
        done
        return 0
    fi

    log_info "Installing deferred npm packages now that Node is available..."
    for entry in "${pending[@]}"; do
        IFS='|' read -r binary package display_name <<< "$entry"
        ensure_npm_global "$binary" "$package" "$display_name"
    done
}
