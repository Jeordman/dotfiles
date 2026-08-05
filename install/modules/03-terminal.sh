#!/usr/bin/env bash

# 03-terminal.sh - Terminal and shell enhancement tools
# Installs zsh, oh-my-zsh, tmux, and modern CLI replacements

# Source libraries if not already loaded (allows standalone execution)
if ! type log_info &> /dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "$SCRIPT_DIR/lib/core.sh"
    source "$SCRIPT_DIR/lib/package-managers.sh"
fi

log_step "Installing Terminal Enhancements"

# Ghostty terminfo for REMOTE machines.
#
# Ghostty sets TERM=xterm-ghostty. That name travels over SSH, but the terminfo
# entry does not — so on a server that doesn't know it, every terminfo-driven
# command fails ("'xterm-ghostty': unknown terminal type") and zsh's line editor
# can't do cursor control, which shows up as garbled, double-echoed input.
#
# ncurses ships a `ghostty` entry but not the `xterm-ghostty` alias Ghostty
# actually sets, so aliasing one to the other is usually all that's needed.
# Compiled into ~/.terminfo, which ncurses searches by default — no sudo.
ensure_ghostty_terminfo() {
    command -v infocmp &> /dev/null || return 0

    if infocmp xterm-ghostty &> /dev/null; then
        log_success "xterm-ghostty terminfo already available"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would compile xterm-ghostty terminfo into ~/.terminfo"
        return 0
    fi

    if ! command -v tic &> /dev/null; then
        log_warning "tic not found — cannot add xterm-ghostty terminfo"
        return 0
    fi

    if ! infocmp ghostty &> /dev/null; then
        # No base entry to alias. Copying from the Ghostty machine is the
        # supported fix; don't guess at a hand-written entry.
        log_warning "No 'ghostty' terminfo entry to alias from"
        log_info "From your Ghostty machine, run:"
        log_info "    infocmp -x xterm-ghostty | ssh $USER@$(hostname) -- tic -x -"
        return 0
    fi

    local src
    src=$(mktemp)
    printf 'xterm-ghostty|Ghostty terminal emulator,\n\tuse=ghostty,\n' > "$src"

    if tic -x -o "$HOME/.terminfo" "$src" 2>/dev/null && infocmp xterm-ghostty &> /dev/null; then
        log_success "Added xterm-ghostty terminfo to ~/.terminfo"
    else
        log_warning "Failed to compile xterm-ghostty terminfo"
    fi
    rm -f "$src"
}

ensure_ghostty_terminfo

# Zsh
ensure_package "zsh" "zsh" "Zsh"

# Tmux
ensure_package "tmux" "tmux" "Tmux"

# Ghostty terminal
if [[ "$OS_TYPE" == "macos" ]]; then
    ensure_package "ghostty" "ghostty" "Ghostty"
else
    # Ghostty installation varies by distro
    if ! command -v ghostty &> /dev/null; then
        case "$PACKAGE_MANAGER" in
            apt)
                log_warning "Ghostty not available in apt repos"
                log_info "Install from: https://github.com/ghostty-org/ghostty"
                ;;
            dnf|pacman)
                log_warning "Ghostty installation may require manual setup"
                log_info "Install from: https://github.com/ghostty-org/ghostty"
                ;;
            *)
                log_warning "Ghostty installation not automated for this package manager"
                log_info "Install from: https://github.com/ghostty-org/ghostty"
                ;;
        esac
    else
        log_success "Ghostty already installed"
    fi
fi

# Modern CLI tools
log_info "Installing modern CLI tools..."

# bat (better cat)
# Debian/Ubuntu ship the binary as `batcat` (clash with an older package), so
# without the alias below `bat` simply isn't on PATH after a successful install.
ensure_package "bat" "bat" "bat"
link_debian_binary_alias "bat" "batcat"

# btop (system monitor)
ensure_package "btop" "btop" "btop"

# eza (better ls)
if [[ "$OS_TYPE" == "macos" ]]; then
    ensure_package "eza" "eza" "eza"
else
    if ! command -v eza &> /dev/null; then
        case "$PACKAGE_MANAGER" in
            apt)
                # eza reached the Debian/Ubuntu repos (Ubuntu 24.04+), so try apt
                # before pulling in a whole Rust toolchain for a directory lister.
                if apt-cache show eza &> /dev/null; then
                    ensure_package "eza" "eza" "eza"
                elif command -v cargo &> /dev/null; then
                    log_info "eza not packaged on this release; installing via cargo..."
                    cargo install eza
                else
                    log_warning "SKIPPED: eza isn't in apt on this release and Rust/Cargo is not installed"
                    log_info "To install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
                    log_info "Then re-run this installer to get eza"
                    record_failed_package "eza"
                fi
                ;;
            dnf|pacman)
                ensure_package "eza" "eza" "eza"
                ;;
            *)
                log_warning "eza installation not automated for this package manager"
                record_failed_package "eza"
                ;;
        esac
    else
        log_success "eza already installed"
    fi
fi

# zoxide (smart cd)
ensure_package "zoxide" "zoxide" "zoxide"

# direnv (per-directory env via .envrc; e.g. per-folder CLAUDE_CONFIG_DIR)
ensure_package "direnv" "direnv" "direnv"

# delta (better git diff)
if [[ "$OS_TYPE" == "macos" ]]; then
    ensure_package "delta" "git-delta" "delta"
else
    ensure_package "delta" "git-delta" "delta"
fi

# thefuck (command correction tool)
ensure_package "thefuck" "thefuck" "thefuck"

# File manager and media tools
log_info "Installing file manager tools..."

# Yazi file manager — no apt package exists on any current Debian/Ubuntu.
#
# Upstream publishes prebuilt binaries, so requiring a full Rust toolchain was
# never necessary: it meant `yazi` and the y() helper in .zshrc were dead on
# every server that didn't happen to have cargo. Pull the release archive
# instead, and keep cargo only as a fallback.
if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    if command -v yazi &> /dev/null; then
        log_success "yazi already installed"
    else
        # Assets are named yazi-<arch>-unknown-linux-gnu.zip
        yazi_arch=$(uname -m)
        case "$yazi_arch" in
            x86_64|amd64)  yazi_target="x86_64-unknown-linux-gnu" ;;
            aarch64|arm64) yazi_target="aarch64-unknown-linux-gnu" ;;
            *)             yazi_target="" ;;
        esac

        if [[ -n "$yazi_target" ]]; then
            # `ya` is yazi's companion CLI (plugin/package management)
            install_from_github_release "sxyazi/yazi" "yazi" \
                "yazi-${yazi_target}.zip" "yazi" "ya"
        fi

        # Fall back to cargo only if the release install didn't produce a binary
        if [[ ! -x "$HOME/.local/bin/yazi" ]] && ! command -v yazi &> /dev/null; then
            if command -v cargo &> /dev/null; then
                log_info "Installing yazi via cargo..."
                cargo install --locked yazi-fm yazi-cli
                log_success "yazi installed"
            elif [[ -z "$yazi_target" ]]; then
                log_warning "SKIPPED: no yazi release binary for architecture $yazi_arch"
                record_failed_package "yazi"
            fi
        fi
    fi
else
    ensure_package "yazi" "yazi" "yazi"
fi

# Yazi dependencies for media preview support
ensure_package "ffmpeg" "ffmpeg" "FFmpeg"

# 7-Zip (package name varies by OS)
if [[ "$OS_TYPE" == "macos" ]]; then
    ensure_package "7z" "p7zip" "7-Zip"
else
    ensure_package "7z" "p7zip-full" "7-Zip"
fi

# The formula is `poppler` on brew but `poppler-utils` on Debian/Ubuntu — asking
# apt for "poppler" fails with "Unable to locate package" on every single run.
if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    ensure_package "pdftoppm" "poppler-utils" "Poppler"
else
    ensure_package "pdftoppm" "poppler" "Poppler"
fi
ensure_package "magick" "imagemagick" "ImageMagick"

# resvg for SVG rendering (may need cargo on some systems)
if [[ "$OS_TYPE" == "macos" ]]; then
    ensure_package "resvg" "resvg" "resvg"
else
    if ! command -v resvg &> /dev/null; then
        if command -v cargo &> /dev/null; then
            log_info "Installing resvg via cargo..."
            cargo install resvg
            log_success "resvg installed"
        else
            log_warning "SKIPPED: resvg requires Rust/Cargo which is not installed"
            log_info "To install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
            log_info "Then re-run this installer to get resvg"
            record_failed_package "resvg"
        fi
    else
        log_success "resvg already installed"
    fi
fi

# Nerd Font for icons (macOS only - Linux users should install manually)
if [[ "$OS_TYPE" == "macos" ]]; then
    if ! brew list --cask font-symbols-only-nerd-font &> /dev/null; then
        log_info "Installing Symbols Nerd Font..."
        brew install --cask font-symbols-only-nerd-font
        log_success "Symbols Nerd Font installed"
    else
        log_success "Symbols Nerd Font already installed"
    fi
fi

# Node Version Manager (NVM)
log_info "Setting up NVM (Node Version Manager)..."
if [ ! -d "$HOME/.nvm" ]; then
    log_info "Installing NVM..."
    # Not `local` — this module runs at top level when executed standalone
    # (see the source guard at the top of the file), where `local` is a syntax error.
    nvm_version="v0.40.0"
    safe_curl_install "https://raw.githubusercontent.com/nvm-sh/nvm/$nvm_version/install.sh" "NVM"

    # Load NVM for current session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # Install latest LTS version of Node.js
    if type nvm &> /dev/null; then
        log_info "Installing Node.js LTS..."
        nvm install --lts
        nvm use --lts
        log_success "Node.js LTS installed"
    else
        log_warning "NVM installed but could not be loaded - restart your shell and run: nvm install --lts"
    fi
else
    log_success "NVM already installed"
    # Ensure NVM is loaded and Node.js is available
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    if type nvm &> /dev/null && ! command -v node &> /dev/null; then
        log_info "NVM loaded but Node.js not found, installing LTS..."
        nvm install --lts
        nvm use --lts
        log_success "Node.js LTS installed"
    fi
fi

# Node exists now, so install anything 02-development.sh had to defer for want
# of npm (tree-sitter CLI, Codex CLI). Without this they need a second full run.
flush_deferred_npm_globals

# Oh My Zsh
log_info "Setting up Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_info "Installing Oh My Zsh..."
    # --keep-zshrc is essential here: without it the oh-my-zsh installer replaces
    # ~/.zshrc with its own template. That clobbers the stowed symlink, so every
    # full install.sh run leaves another ~/.zshrc.backup.<timestamp> behind and
    # briefly drops the real config. 05-dotfiles.sh re-links it afterwards, but
    # only because it runs later — don't rely on that ordering.
    safe_curl_install "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" "Oh My Zsh" "--unattended --keep-zshrc"
else
    log_success "Oh My Zsh already installed"
fi

# Zsh plugins
log_info "Installing Zsh plugins..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# zsh-autosuggestions
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    log_info "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    log_success "zsh-autosuggestions installed"
else
    log_success "zsh-autosuggestions already installed"
fi

# zsh-syntax-highlighting
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    log_info "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    log_success "zsh-syntax-highlighting installed"
else
    log_success "zsh-syntax-highlighting already installed"
fi

# Powerlevel10k theme
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    log_info "Installing Powerlevel10k theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
    log_success "Powerlevel10k installed"
else
    log_success "Powerlevel10k already installed"
fi

# Tmux Plugin Manager (TPM)
log_info "Setting up Tmux Plugin Manager..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    log_info "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
    log_success "TPM installed"
else
    log_success "TPM already installed"
fi

# Change default shell to zsh
#
# Compare against the LOGIN shell in passwd, not $SHELL: $SHELL is inherited from
# whatever launched install.sh and doesn't change when chsh succeeds, so the old
# check could report success while the login shell was still bash.
#
# chsh authenticates via PAM and prompts for a password. That fails outright on
# SSH-key-only accounts with no usable password ("PAM: Authentication failure"),
# which is the normal setup on a cloud server — so fall back to `sudo chsh`,
# which changes another user's shell without needing that user's password.
if command -v zsh &> /dev/null; then
    zsh_path=$(command -v zsh)
    current_login_shell=$(get_login_shell)

    # Accept ANY zsh, not just the one first on PATH. On macOS `command -v zsh`
    # finds Homebrew's /opt/homebrew/bin/zsh while the login shell is usually
    # Apple's /bin/zsh; demanding an exact match would try to chsh (and prompt
    # for a sudo password) on every single run for no real benefit.
    if [[ "$current_login_shell" == "$zsh_path" || "$current_login_shell" == */zsh ]]; then
        log_success "Default shell is already zsh ($current_login_shell)"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would change default shell to $zsh_path"
    else
        # NEVER redirect stderr on the commands below.
        #
        # chsh and sudo write their "Password:" prompt to stderr. Sending that to
        # /dev/null doesn't make them non-interactive — it hides the prompt while
        # they sit there waiting for input, so the installer looks frozen at
        # "Changing default shell to zsh..." with no indication it wants
        # anything. Try the non-interactive routes FIRST, and when a prompt is
        # genuinely needed, announce it and let it be seen.

        # zsh must be listed in /etc/shells or chsh refuses it
        if [ -f /etc/shells ] && ! grep -qx "$zsh_path" /etc/shells; then
            if sudo -n true 2>/dev/null; then
                echo "$zsh_path" | sudo -n tee -a /etc/shells > /dev/null \
                    && log_success "Added $zsh_path to /etc/shells"
            else
                log_info "Adding $zsh_path to /etc/shells (sudo will ask for your password)"
                echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null \
                    || log_warning "Could not add $zsh_path to /etc/shells"
            fi
        fi

        log_info "Changing default shell to zsh..."

        shell_changed=false

        # 1. Passwordless sudo — silent and instant when available.
        if sudo -n true 2>/dev/null && sudo -n chsh -s "$zsh_path" "$USER" 2>/dev/null; then
            log_success "Default shell changed to zsh (passwordless sudo)"
            shell_changed=true
        else
            # 2. Interactive. Warn BEFORE blocking, and leave stderr alone so the
            #    password prompt is actually visible.
            log_warning "This step needs a password — a prompt will appear below."
            log_info "Press Ctrl-C to skip; you can always run it later with:"
            log_info "    sudo chsh -s $zsh_path $USER"

            if chsh -s "$zsh_path"; then
                log_success "Default shell changed to zsh"
                shell_changed=true
            elif sudo chsh -s "$zsh_path" "$USER"; then
                log_success "Default shell changed to zsh (via sudo)"
                shell_changed=true
            fi
        fi

        if [[ "$shell_changed" != "true" ]]; then
            log_warning "Could not change the default shell automatically"
            log_info "chsh needs a password this account may not have (SSH-key-only)."
            log_info "Run this by hand:  sudo chsh -s $zsh_path $USER"
        fi

        # Report what actually took effect rather than assuming
        current_login_shell=$(get_login_shell)
        if [[ "$current_login_shell" == "$zsh_path" || "$current_login_shell" == */zsh ]]; then
            log_info "Login shell is now $current_login_shell (takes effect next login)"
        else
            log_warning "Login shell is still $current_login_shell"
        fi
    fi
fi

log_success "Terminal enhancements installation complete"
