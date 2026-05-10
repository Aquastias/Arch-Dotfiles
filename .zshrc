# ===============================
# Zsh Configuration with Zinit
# ===============================

# Load environment variables
source "$HOME/.zshenv"

# Vi keybindings
bindkey -e

# Set LS_COLORS
eval "$(dircolors -b)"

ZSH_BASE_DIR="$HOME/.zsh"

# Standard
source "$ZSH_BASE_DIR/autoload/default.zsh"
source "$ZSH_BASE_DIR/history/default.zsh"
source "$ZSH_BASE_DIR/zinit/default.zsh"
source "$ZSH_BASE_DIR/zstyle/default.zsh"

source "$ZSH_BASE_DIR/vendors/p10k/default.zsh"
source "$ZSH_BASE_DIR/vendors/nodejs/nvm/default.zsh"

# Load aliases and topic functions
[[ -f $ZSH_ALIASES ]] && source $ZSH_ALIASES

for file in "$ZSH_BASE_DIR/topics"/*.zsh; do
  [[ -f "$file" ]] && source "$file"
done

# Syntax highlighting theme (loaded later for performance)
SYNTAX_THEME="$HOME/.zsh/syntax-highlighting/themes/catppuccin-mocha.zsh"
[[ -f "$SYNTAX_THEME" ]] && source "$SYNTAX_THEME"

# Suppress P10k prompt on initialization
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# Initialize zoxide (must be last)
eval "$(zoxide init zsh)"
