# Variables
ZPLUG="$HOME/.zplug";
ZPLUG_REPO_URL="https://github.com/zplug/zplug"
ZPLUG_INIT_PATH="/usr/share/zsh/scripts/zplug/init.zsh"
ZSH_FUNCTIONS_PATH="$HOME/.zfunc"
ZSH_ALIASES="$HOME/.zsh_aliases"

# Use vi keybindings even if our EDITOR is set to vi.
bindkey -e

#  Keep 5000 lines of history within the shell and save it to ~/.histfile.
setopt histignorealldups sharehistory
HISTFILE=~/.histfile
HISTSIZE=5000
SAVEHIST=5000

# Set up the prompt.
autoload -Uz promptinit
promptinit

# Use modern completion system.
autoload -Uz compinit
compinit -C

# Find compinstall statements and update them.
zstyle :compinstall filename '$HOME/.zshrc'

# Functions
if [[ $(ls -A $ZSH_FUNCTIONS_PATH | wc -l) -gt 0 ]]; then
  for file in $ZSH_FUNCTIONS_PATH/**; do
    if [[ -f $file ]]; then
      autoload $file;
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
zplug "plugins/fzf", from:oh-my-zsh
zplug "plugins/nvm", from:oh-my-zsh
zplug "plugins/alias-finder", from:oh-my-zsh
zplug "plugins/archlinux", from:oh-my-zsh
zplug "plugins/command-not-found", from:oh-my-zsh
zplug "plugins/common-aliases", from:oh-my-zsh
zplug "plugins/colorize", from:oh-my-zsh
zplug "plugins/docker", from:oh-my-zsh
zplug "plugins/docker-compose", from:oh-my-zsh
zplug "plugins/git", from:oh-my-zsh
zplug "plugins/git-auto-fetch", from:oh-my-zsh
zplug "plugins/git-extras", from:oh-my-zsh
zplug "plugins/man", from:oh-my-zsh
zplug "plugins/rebar", from:oh-my-zsh
zplug "plugins/sudo", from:oh-my-zsh
zplug "plugins/systemd", from:oh-my-zsh
zplug "plugins/urltools", from:oh-my-zsh
zplug "plugins/zsh-interactive-cd", from:oh-my-zsh
zplug "plugins/zsh-navigation-tools", from:oh-my-zsh
zplug "zplug/zplug", hook-build: "zplug --self-manage"
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-completions"
zplug "zsh-users/zsh-history-substring-search"
zplug "zsh-users/zsh-syntax-highlighting"

# Theme
zplug "themes/robbyrussell", from:oh-my-zsh
#zplug "themes/half-life", from:oh-my-zsh

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

#Display Pokemon
krabby random | tail -n +2

# Init zoxide, a smarter cd command
eval "$(zoxide init --cmd cd zsh)"

export EDITOR="nvim"
export VISUAL="nvim"
