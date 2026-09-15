## ZSH
export ZSHRC_SOURCE="$HOME/.zshrc"
export ZSH_ALIASES="$HOME/.zsh_aliases"

## Sudo
export SUDO="sudo"

## Dotfiles
export DOTFILES="$HOME/.dotfiles"

# NVM — Arch installs nvm under /usr/share/nvm; point NVM_DIR there so the OMZ
# nvm plugin (lazy) can find and source it (no eager /usr/share/nvm source).
export NVM_DIR="/usr/share/nvm"

# Zoxide
export ZOXIDE_CMD_OVERRIDE="cd"
###

### Exportable
export EDITOR="nvim"
export VISUAL="nvim"
export PATH="$HOME/.local/bin:$PATH"

# FZF_DEFAULT_OPTS is set by the Noctalia-generated ~/.zsh/themes/noctalia.zsh
# (palette-following), not here.

# bat: syntax-highlighted cat/pager (php/json/bash/css/scss/html/js/ts/yaml/c/
# cpp…). Theme 'ansi' renders via the terminal's 16 ANSI colours, so bat follows
# the Noctalia palette live for free — same principle as the syntax-highlighter.
export BAT_THEME="ansi"

# eza: file-type colors come from LS_COLORS (dircolors), but eza's own UI
# fields (permissions/size/date/owner/git) default to its built-in palette.
# Map them to ANSI-16 SGR codes so they render through the terminal's 16
# colours — following Noctalia live on compositors, fixed Sapphire under KDE
# (ADR 0132). No 38;5;/38;2; hex, so nothing is pinned off-palette.
export EZA_COLORS="ur=33:uw=31:ux=32:ue=32:gr=33:gw=31:gx=32:tr=33:tw=31:tx=32:su=33:sf=33:xa=36:sn=32:sb=32:df=34:ds=34:uu=33:gu=33:un=90:gn=90:da=34:ga=32:gm=33:gd=31:gv=35:gt=36:xx=90:in=90:bl=90"

## Grub
export GRUB_DEFAULT_FILE="/etc/default/grub"
export GRUB_BOOT_CFG="/boot/grub/grub.cfg"
###
