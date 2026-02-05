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

source $ZSH/oh-my-zsh.sh

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

# NVM (Node Version Manager) setup
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"        # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Initialize zoxide (smarter cd command)
eval "$(zoxide init zsh)"

# Yazi change directory on exit
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

alias v='nvim'
alias c='claude'
alias multipull="find . -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print -exec git -C {} pull \;"
# alias multimain='find . -mindepth 1 -maxdepth 1 -type d -print -exec sh -c '\''cd "$1" && (git checkout main 2>/dev/null || git checkout master)'\'' _ {} \;'
# alias multi='multimain && multipull'
alias multi='multipull'
alias l="eza --icons --group-directories-first --no-filesize"

# Tmux attach with auto-create - if no sessions exist, create one
tmux() {
  # Check if the first argument is 'a' or 'attach' or 'attach-session'
  if [[ "$1" == "a" || "$1" == "attach" || "$1" == "attach-session" ]]; then
    # Check if there are any tmux sessions
    if ! command tmux has-session 2>/dev/null; then
      # No sessions exist, create a new default one
      echo "No tmux sessions found. Creating new session..."
      # Check if btop exists and create session accordingly
      if command -v btop &> /dev/null; then
        # Navigate to unicity (if it exists) and create session with btop in a window named pulse
        if command -v zoxide &> /dev/null && zoxide query uni &> /dev/null; then
          local uni_dir
          uni_dir=$(zoxide query uni)
          command tmux new-session -d -s "THE SPIRE" -n "pulse" -c "$uni_dir" "btop"
        else
          command tmux new-session -d -s "THE SPIRE" -n "pulse" -c ~ "btop"
        fi
      else
        # Create session with default shell
        command tmux new-session -d -s "THE SPIRE" -c ~
      fi
      command tmux attach-session -t "THE SPIRE"
    else
      # Session exists, proceed normally
      command tmux "$@"
    fi
  else
    # For all other tmux commands, pass through normally
    command tmux "$@"
  fi
}

eval "$(thefuck --alias)"

# run 'l' to list files after cd
chpwd() {
  l
}

# ctrl-x to edit command line
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X' edit-command-line

# Source local configuration for secrets and machine-specific settings (not tracked in git)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
