#!/usr/bin/env bash

# 02-development.sh - Development tools installation
# Installs core development tools and utilities

# Source libraries if not already loaded (allows standalone execution)
if ! type log_info &> /dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "$SCRIPT_DIR/lib/core.sh"
    source "$SCRIPT_DIR/lib/package-managers.sh"
fi

log_step "Installing Development Tools"

# Neovim
ensure_package "nvim" "neovim" "Neovim"

# tree-sitter CLI (required by nvim-treesitter main branch to compile parsers)
# Note: brew 'tree-sitter' is the C library only; the CLI comes from npm.
# On a fresh box npm doesn't exist yet — nvm is installed in 03-terminal.sh,
# which runs AFTER this module. ensure_npm_global queues it in that case and
# 03-terminal.sh installs it once Node is up, so one run of install.sh is enough.
ensure_npm_global "tree-sitter" "tree-sitter-cli" "tree-sitter CLI"

# Ripgrep (used by Telescope in neovim)
ensure_package "rg" "ripgrep" "ripgrep"

# fzf (fuzzy finder)
ensure_package "fzf" "fzf" "fzf"

# fd (fast find alternative, used by Telescope)
# Debian/Ubuntu ship the binary as `fdfind` to avoid a clash with an older
# package, so the alias below is what actually puts `fd` on PATH.
if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    ensure_package "fd" "fd-find" "fd"
    link_debian_binary_alias "fd" "fdfind"
else
    ensure_package "fd" "fd" "fd"
fi

# lazygit (git UI in neovim) — not packaged for apt at all
if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    install_from_github_release "jesseduffield/lazygit" "lazygit" "Linux_x86_64.tar.gz" "lazygit"
else
    ensure_package "lazygit" "lazygit" "lazygit"
fi

# jq (JSON processor)
ensure_package "jq" "jq" "jq"

# git-gtr (worktree runner)
if ! command -v git-gtr &> /dev/null; then
    if [[ "$OS_TYPE" == "macos" ]] && command -v brew &> /dev/null; then
        log_info "Installing git-gtr..."
        brew tap coderabbitai/tap &> /dev/null || true
        brew install git-gtr && log_success "git-gtr installed"
    else
        log_warning "git-gtr install only automated on macOS+brew. See https://github.com/coderabbitai/git-worktree-runner"
    fi
else
    log_success "git-gtr already installed"
fi

# Maestro (mobile UI testing — used by the sim-loop skill for iOS work, e.g. topout app)
# macOS only: it drives iOS simulators, which don't exist elsewhere. This also has
# to be guarded because `brew` isn't present on a stock Linux box, and the bare
# `brew install ... && log_success` below would abort the whole run under `set -e`.
if [[ "$OS_TYPE" == "macos" ]]; then
    # Requires Temurin JDK (Maestro runs on the JVM)
    if ! brew list --cask temurin &> /dev/null; then
        log_info "Installing Temurin JDK (required by Maestro)..."
        brew install --cask temurin && log_success "Temurin installed"
    else
        log_success "Temurin already installed"
    fi
    # NOTE: do NOT use `brew install maestro` — that installs a music app, not the testing tool
    if ! command -v maestro &> /dev/null; then
        log_info "Installing Maestro..."
        curl -Ls "https://get.maestro.mobile.dev" | bash && log_success "Maestro installed"
    else
        log_success "Maestro already installed"
    fi
else
    log_info "Skipping Temurin + Maestro (iOS simulator tooling, macOS only)"
fi

# GitHub CLI
if [[ "$OS_TYPE" == "macos" ]]; then
    ensure_package "gh" "gh" "GitHub CLI"
else
    # Install gh on Linux
    if ! command -v gh &> /dev/null; then
        case "$PACKAGE_MANAGER" in
            apt)
                log_info "Installing GitHub CLI..."
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                sudo apt update
                install_package "gh" "GitHub CLI"
                ;;
            dnf)
                sudo dnf install 'dnf-command(config-manager)'
                sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
                install_package "gh" "GitHub CLI"
                ;;
            *)
                log_warning "GitHub CLI installation not automated for this package manager"
                log_info "Install manually from: https://github.com/cli/cli#installation"
                ;;
        esac
    else
        log_success "GitHub CLI already installed"
    fi
fi

# Claude Code (Anthropic CLI)
if ! command -v claude &> /dev/null; then
    log_info "Installing Claude Code..."
    safe_curl_install "https://claude.ai/install.sh" "Claude Code"
else
    log_success "Claude Code already installed"
fi

# Codex CLI (OpenAI) — npm-only, and npm may not exist yet (see tree-sitter above)
ensure_npm_global "codex" "@openai/codex" "Codex CLI"

log_success "Development tools installation complete"
