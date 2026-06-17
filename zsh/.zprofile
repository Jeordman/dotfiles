# ~/.zprofile — login-shell setup, sourced BEFORE ~/.zshrc (and therefore before
# Powerlevel10k's instant prompt). KEEP THIS MINIMAL AND FAST: anything slow here
# delays every new terminal, because the prompt can't appear until it finishes.
#
# In particular, do NOT source nvm.sh here (it costs ~1s). node/npm/npx are put
# on PATH, and nvm is lazy-loaded, in ~/.zshrc instead.

# Homebrew — use whichever prefix exists (Apple Silicon, Intel, or Linuxbrew).
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  if [ -x "$_brew" ]; then
    eval "$("$_brew" shellenv)"
    break
  fi
done
unset _brew

export NVM_DIR="$HOME/.nvm"
