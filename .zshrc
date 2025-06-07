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
