# ===============================
# Zsh Configuration with Zinit
# ===============================

# Load environment variables
source "$HOME/.zshenv"

# Vi keybindings
bindkey -e

ZSH_BASE_DIR="$HOME/.zsh"

# Standard
source "$ZSH_BASE_DIR/autoload/default.zsh"
source "$ZSH_BASE_DIR/history/default.zsh"
source "$ZSH_BASE_DIR/zinit/default.zsh"
source "$ZSH_BASE_DIR/zstyle/default.zsh"

source "$ZSH_BASE_DIR/vendors/p10k/default.zsh"
source "$ZSH_BASE_DIR/vendors/nodejs/nvm/default.zsh"

# Load aliases and functions
[[ -f $ZSH_ALIASES ]] && source $ZSH_ALIASES

if [[ -n "$ZSH_FUNCTIONS_PATH" && -d "$ZSH_FUNCTIONS_PATH" ]]; then
  for file in $ZSH_FUNCTIONS_PATH/**/*(.); do
    autoload -Uz "$file"
  done
fi

# Syntax highlighting theme (loaded later for performance)
SYNTAX_THEME="$HOME/.zsh/syntax-highlighting/themes/catppuccin-mocha.zsh"
[[ -f "$SYNTAX_THEME" ]] && source "$SYNTAX_THEME"

  ### ZNT's installer added snippet ###
  fpath=( "$fpath[@]" "$HOME/.config/znt/zsh-navigation-tools" )
  autoload n-aliases n-cd n-env n-functions n-history n-kill n-list n-list-draw n-list-input n-options n-panelize n-help
  autoload znt-usetty-wrapper znt-history-widget znt-cd-widget znt-kill-widget
  alias naliases=n-aliases ncd=n-cd nenv=n-env nfunctions=n-functions nhistory=n-history
  alias nkill=n-kill noptions=n-options npanelize=n-panelize nhelp=n-help
  zle -N znt-history-widget
  bindkey '^R' znt-history-widget
  setopt AUTO_PUSHD HIST_IGNORE_DUPS PUSHD_IGNORE_DUPS
  zstyle ':completion::complete:n-kill::bits' matcher 'r:|=** l:|=*'
  ### END ###

