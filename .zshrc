# Variables
source "$HOME/.zshenv"

# Syntax highlighting
source "$HOME/.zsh/syntax-highlighting/themes/catppuccin-mocha.zsh"

# Use vi keybindings even if our EDITOR is set to vi.
bindkey -e

#  Keep 5000 lines of history within the shell and save it to ~/.histfile.
setopt histignorealldups sharehistory
HISTFILE=~/.histfile
HISTSIZE=5000
SAVEHIST=5000
HISTORY_IGNORE=("*sudo -S*")

# Set up the prompt.
autoload -Uz promptinit
promptinit

# Use modern completion system.
autoload -Uz compinit
compinit -C

# Find compinstall statements and update them.
zstyle :compinstall filename "$HOME/.zshrc"

# Functions
if [[ $(ls -A $ZSH_FUNCTIONS_PATH | wc -l) -gt 0 ]]; then
  for file in $ZSH_FUNCTIONS_PATH/**; do
    if [[ -f $file ]]; then
      autoload $file
    fi
  done
fi

# Aliases
[[ -f $ZSH_ALIASES ]] && source $ZSH_ALIASES

# START - zplug
# Check if zplug is installed.
if [[ ! -d $ZPLUG ]]; then
  git clone $ZPLUG_REPO_URL $ZPLUG
  source $ZPLUG/init.zsh && zplug update --self
fi

# Essential
source $ZPLUG_INIT_PATH

# Plugins
zplug "plugins/aliases", from:oh-my-zsh
zplug "plugins/alias-finder", from:oh-my-zsh
zplug "plugins/archlinux", from:oh-my-zsh
zplug "plugins/colored-man-pages", from:oh-my-zsh
zplug "plugins/colorize", from:oh-my-zsh
zplug "plugins/command-not-found", from:oh-my-zsh
zplug "plugins/common-aliases", from:oh-my-zsh
zplug "plugins/cp", from:oh-my-zsh
zplug "plugins/docker-compose", from:oh-my-zsh
zplug "plugins/docker", from:oh-my-zsh
zplug "plugins/dotenv", from:oh-my-zsh
zplug "plugins/extract", from:oh-my-zsh
zplug "plugins/eza", from:oh-my-zsh
zplug "plugins/firewalld", from:oh-my-zsh
zplug "plugins/fzf", from:oh-my-zsh
zplug "plugins/git-auto-fetch", from:oh-my-zsh
zplug "plugins/git-extras", from:oh-my-zsh
zplug "plugins/git", from:oh-my-zsh
zplug "plugins/gnu-utils", from:oh-my-zsh
zplug "plugins/gpg-agent", from:oh-my-zsh
zplug "plugins/history-substring-search", from:oh-my-zsh
zplug "plugins/history", from:oh-my-zsh
zplug "plugins/nvm", from:oh-my-zsh
zplug "plugins/node", from:oh-my-zsh
zplug "plugins/nvm", from:oh-my-zsh
zplug "plugins/pass", from:oh-my-zsh
zplug "plugins/podman", from:oh-my-zsh
zplug "plugins/ssh-agent", from:oh-my-zsh
zplug "plugins/ssh", from:oh-my-zsh
zplug "plugins/sudo", from:oh-my-zsh
zplug "plugins/systemd", from:oh-my-zsh
zplug "plugins/urltools", from:oh-my-zsh
zplug "plugins/web-search", from:oh-my-zsh
zplug "plugins/zoxide", from:oh-my-zsh
zplug "plugins/zsh-interactive-cd", from:oh-my-zsh
zplug "plugins/zsh-navigation-tools", from:oh-my-zsh
zplug "zplug/zplug", hook-build: "zplug --self-manage"
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-completions"
zplug "zsh-users/zsh-syntax-highlighting"
zplug "baliestri/pnpm.plugin.zsh"

# Theme
#zplug "themes/robbyrussell", from:oh-my-zsh
zplug "themes/half-life", from:oh-my-zsh

# Configurations
# - Eza
zstyle ':omz:plugins:eza' 'dirs-first' yes
zstyle ':omz:plugins:eza' 'git-status' yes
zstyle ':omz:plugins:eza' 'header' yes
zstyle ':omz:plugins:eza' 'show-group' yes
zstyle ':omz:plugins:eza' 'size-prefix' si

# - SSH
zstyle :omz:plugins:ssh-agent quiet yes
zstyle :omz:plugins:ssh-agent agent-forwarding yes
zstyle :omz:plugins:ssh-agent lazy yes

# Install/load new plugins when zsh is started or reloaded.
if ! zplug check --verbose; then
  printf "Install? [y/N]: "

  if read -q; then
    echo
    zplug install
  fi
fi

zplug load
# END - zplug

# Display Pokemon
krabby random | tail -n +2

# NVM - NodeJs version manager
source /usr/share/nvm/init-nvm.sh
