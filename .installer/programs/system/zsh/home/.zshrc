# =============================================================================
# ~/.zshrc — interactive zsh (Zinit + Powerlevel10k)
# =============================================================================

# Powerlevel10k instant prompt. MUST stay at the very top: anything that prints
# to the console or reads input has to go ABOVE this block. `quiet` suppresses
# instant-prompt warnings (set here, before the block — not after, or it is a
# no-op).
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
_p10k_ip="${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
[[ -r "$_p10k_ip" ]] && source "$_p10k_ip"
unset _p10k_ip

# Emacs keybindings.
bindkey -e

# LS_COLORS
eval "$(dircolors -b)"

ZSH_BASE_DIR="$HOME/.zsh"

# Standard. zstyle before zinit: the OMZ plugin options (ssh-agent quiet/lazy,
# eza, nvm lazy) are zstyles the plugins read at load time, so they must be set
# before zinit sources the plugins — otherwise they no-op (ssh-agent then prints
# "Starting ssh-agent" after p10k's instant-prompt preamble, corrupting async).
source "$ZSH_BASE_DIR/autoload/default.zsh"
source "$ZSH_BASE_DIR/history/default.zsh"
source "$ZSH_BASE_DIR/zstyle/default.zsh"
source "$ZSH_BASE_DIR/zinit/default.zsh"

# compinit runs HERE, after zinit added plugin completions (zsh-completions) to
# fpath — otherwise their functions miss the dump. -C trusts the dump for speed.
compinit -C

# Powerlevel10k (loads via zinit, then sources ~/.p10k.zsh + accent override).
source "$ZSH_BASE_DIR/vendors/p10k/default.zsh"

# Load aliases and topic functions
[[ -f $ZSH_ALIASES ]] && source $ZSH_ALIASES

for file in "$ZSH_BASE_DIR/topics"/*.zsh; do
  [[ -f "$file" ]] && source "$file"
done

# Noctalia-generated theme: FZF_DEFAULT_OPTS + zsh-syntax-highlighting styles.
# Seed-only, rewritten live on palette change in compositor sessions; a seed
# ships so first boot has it. Sourced after the highlighter is loaded.
[[ -f "$HOME/.zsh/themes/noctalia.zsh" ]] \
  && source "$HOME/.zsh/themes/noctalia.zsh"

# Initialize zoxide (must be last)
eval "$(zoxide init zsh)"
