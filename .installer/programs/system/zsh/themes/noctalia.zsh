# SEED — resolved copy of templates/zsh.zsh for the fleet default palette
# (Catppuccin Mocha Sapphire, ADR 0109). install.sh copies this to
# ~/.zsh/themes/noctalia.zsh and /etc/skel so first boot / KDE has color before
# Noctalia ever runs the template. Noctalia overwrites it live in compositor
# sessions. Keep the key set in sync with templates/zsh.zsh (asserted by tests).

# ── fzf ──────────────────────────────────────────────────────────────────────
export FZF_DEFAULT_OPTS="--color=bg+:#313244,bg:#181825,spinner:#74c7ec,hl:#74c7ec,fg:#cdd6f4,header:#74c7ec,info:#74c7ec,pointer:#74c7ec,marker:#a6e3a1,fg+:#cdd6f4,prompt:#74c7ec,hl+:#74c7ec"

# ── zsh-syntax-highlighting ──────────────────────────────────────────────────
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main cursor)
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[comment]='fg=#6c7086'
ZSH_HIGHLIGHT_STYLES[command]='fg=#74c7ec'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#74c7ec'
ZSH_HIGHLIGHT_STYLES[function]='fg=#74c7ec'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#a6e3a1'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#a6e3a1,italic'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#89dceb'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#89dceb'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#f9e2af'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#f9e2af'
ZSH_HIGHLIGHT_STYLES[path]='fg=#cdd6f4,underline'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#89b4fa'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#f38ba8,bold'
