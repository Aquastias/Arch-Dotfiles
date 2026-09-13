# Eza plugin options
zstyle ':omz:plugins:eza' dirs-first yes
zstyle ':omz:plugins:eza' git-status yes
zstyle ':omz:plugins:eza' header yes
zstyle ':omz:plugins:eza' show-group yes
zstyle ':omz:plugins:eza' size-prefix si
# --icons=auto: per-filetype nerd-font glyphs in listings (js/ts/php/json/yaml/
# html/css/scss/c/cpp/sh…). eza colours are on by default (its own theme).
zstyle ':omz:plugins:eza' icons yes

# NVM plugin: lazy-load (defer nvm until first `nvm`/`node`/`npm` use) so shell
# startup stays fast. OMZ's nvm plugin is the single init — no eager
# /usr/share/nvm source.
zstyle ':omz:plugins:nvm' lazy yes

# SSH Agent plugin options
zstyle :omz:plugins:ssh-agent quiet yes
zstyle :omz:plugins:ssh-agent agent-forwarding yes
zstyle :omz:plugins:ssh-agent lazy yes
