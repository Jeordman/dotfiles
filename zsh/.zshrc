# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)

# Guarded: if install.sh aborted before it could fetch oh-my-zsh (or you're on a
# box with only the bare zsh binary), an unguarded source kills the shell here —
# you get "no such file or directory" and NONE of the config below runs, so no
# aliases, no functions, no keybindings. Degrade to a plain-but-working zsh
# instead, and say what to run to fix it.
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  print -u2 "zsh: oh-my-zsh missing — run: bash ~/dotfiles/install/modules/03-terminal.sh"
  autoload -Uz compinit && compinit -u
  autoload -Uz vcs_info
  precmd_functions+=(vcs_info)
  zstyle ':vcs_info:git:*' formats ' (%b)'
  setopt PROMPT_SUBST
  PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%F{yellow}${vcs_info_msg_0_}%f$ '
fi

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
  export VISUAL='vim'
else
  export EDITOR='nvim'
  export VISUAL='nvim'
fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# NVM — lazy. Sourcing nvm.sh on every shell costs ~1s because nvm resolves the
# default `lts/*` alias and runs `nvm use`. Instead: put the newest installed
# node on PATH directly (so node/npm/npx work instantly, including shebang
# scripts), and only source the full nvm the first time you actually run `nvm`
# to switch or install a version.
export NVM_DIR="$HOME/.nvm"
_nvm_bins=("$NVM_DIR"/versions/node/*/bin(N))  # (N) = no error if none installed
if (( $#_nvm_bins )); then
  _nvm_bin=$(printf '%s\n' "${_nvm_bins[@]}" | sort -V | tail -1)  # newest version
  export PATH="$_nvm_bin:$PATH"
fi
unset _nvm_bins _nvm_bin
nvm() {  # first call swaps this stub for the real nvm, then runs your command
  unset -f nvm
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
  nvm "$@"
}

# Initialize zoxide (smarter cd command)
# Exclude git worktree directories from zoxide so they don't pollute search results.
# Convention: worktree parent folders always end in "-worktrees" (new-shop-worktrees,
# UFeelGreat-worktrees, dotfiles-worktrees, ...). This matches any such folder anywhere under
# $HOME and everything inside it, so new ones are ignored automatically without being listed.
# Real repos (new-shop, global-cms, UFeelGreat, ...) are unaffected.
export _ZO_EXCLUDE_DIRS="$HOME/**/*-worktrees:$HOME/**/*-worktrees/**"
# Guarded like fzf/direnv below — on a box where zoxide didn't install, an
# unguarded eval prints an error on every single new shell.
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# Yazi change directory on exit
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

alias v='nvim'
alias c='claude'  # naming is handled by the claude() wrapper further down
alias h='herdr'
alias cc='codex'
alias cr='codex exec review --base main --uncommitted'
alias multipull="find . -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print -exec git -C {} pull \;"
# alias multimain='find . -mindepth 1 -maxdepth 1 -type d -print -exec sh -c '\''cd "$1" && (git checkout main 2>/dev/null || git checkout master)'\'' _ {} \;'
# alias multi='multimain && multipull'
alias multi='multipull'
# chpwd() below runs `l` after every cd, so this must never be a missing command.
if command -v eza >/dev/null; then
  alias l="eza --icons --group-directories-first --no-filesize"
else
  alias l="ls -lh --color=auto"
fi
alias zhome='for dir in ~/*/; do zoxide add "$dir"; done'

# Name every Remote Control session after its git worktree.
# All sessions run with remoteControlAtStartup, so each one appears in
# claude.ai/code and the phone app. Left alone, that row gets titled from the
# conversation (or `hostname-xxxx`), which is unusable when nine worktrees of the
# same repo are connected at once. `--remote-control <name>` pins the row title
# to the worktree AND marks it definitive, so Claude stops re-titling it from
# messages later. CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX (set in chpwd below)
# only seeds the *fallback* title, which is why setting it alone never stuck.
claude() {
  local arg passthrough=0
  # xhigh is the working default. It is pinned here rather than in settings.json
  # because /effort rewrites that file's effortLevel mid-session, which silently
  # changes every session started afterwards. A launch flag outranks the file, so
  # the drift stops mattering. An explicit --effort still wins over this.
  local -a effort=(--effort xhigh)

  # Subcommands and non-interactive/other-transport modes get no name injected.
  case "${1-}" in
    agents|auth|auto-mode|doctor|gateway|import|install|mcp|plugin|plugins|project|setup-token|ultrareview|update|upgrade)
      passthrough=1 ;;
  esac
  for arg in "$@"; do
    case "$arg" in
      -p|--print|-n|--name|--name=*|--remote-control|--remote-control=*|--cloud|--cloud=*|--bg|--background|-w|--worktree|--worktree=*)
        passthrough=1 ;;
      --effort|--effort=*) effort=() ;;
    esac
  done
  if (( passthrough )); then
    command claude "$@"
    return
  fi

  # Worktree root, not $PWD — running claude from apps/shop should still say
  # which worktree it is.
  local name="${PWD:t}" root
  root=$(command git rev-parse --show-toplevel 2>/dev/null) && name="${root:t}"
  command claude --remote-control "$name" "${effort[@]}" "$@"
}

# thefuck is Python-based and has no working package on recent Ubuntu (Python 3.12),
# so this must be guarded or every new shell on those boxes starts with a traceback.
command -v thefuck >/dev/null && eval "$(thefuck --alias)"

# run 'l' to list files after cd
chpwd() {
  l
  # Name auto-started Claude Code remote sessions after the current folder/worktree
  export CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX="${PWD:t}"
}
# Seed the prefix for the shell's starting dir (chpwd only fires on cd)
export CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX="${PWD:t}"

# ctrl-x to edit command line
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X' edit-command-line

# fzf widgets: ctrl+r (history), ctrl+t (files), alt+c (cd)
command -v fzf >/dev/null && source <(fzf --zsh)

# Source local configuration for secrets and machine-specific settings (not tracked in git)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

export PATH="$HOME/.local/bin:$PATH"

# pnpm — path differs by OS; the hardcoded /Users/... form is dead weight on Linux
if [[ "$OSTYPE" == darwin* ]]; then
  export PNPM_HOME="$HOME/Library/pnpm"
else
  export PNPM_HOME="$HOME/.local/share/pnpm"
fi
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
export PATH=$PATH:$HOME/.maestro/bin

# direnv — loads/unloads per-directory env (.envrc) on cd. Keep near the end.
# Guarded so shells don't error on machines where direnv isn't installed yet.
command -v direnv >/dev/null && eval "$(direnv hook zsh)"
