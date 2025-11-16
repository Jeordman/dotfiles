# Clone with submodules
cd ~
git clone --recurse-submodules <your-dotfiles-repo-url> dotfiles

# Download GNU Stow
brew install stow

# Then stow everything
cd ~/dotfiles
stow nvim tmux zsh ghostty
