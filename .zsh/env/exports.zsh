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

## Grub
export GRUB_DEFAULT_FILE="/etc/default/grub"
export GRUB_BOOT_CFG="/boot/grub/grub.cfg"
###
