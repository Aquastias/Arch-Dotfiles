# Noctalia user-template (stowed input). Registered in config.toml as
# [theme.templates.user.p10k-accent]; Noctalia writes the resolved output to
# ~/.zsh/themes/p10k-accent.zsh, sourced by ~/.zsh/vendors/p10k/default.zsh
# AFTER ~/.p10k.zsh so these win. Only the accent-carrying Powerlevel10k
# foregrounds follow the palette; every other prompt setting stays the fixed
# committed .p10k.zsh (the 491-key config is not live-followed — ADR 0128 term
# "Zsh Theme Template"). p10k accepts #rrggbb foregrounds on truecolor terminals.

typeset -g POWERLEVEL9K_DIR_FOREGROUND='{{colors.primary.default.hex}}'
typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND='{{colors.primary.default.hex}}'
typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND='{{colors.on_surface_variant.default.hex}}'
typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND='{{colors.primary.default.hex}}'
