# Noctalia user-template (stowed input). Registered in config.toml as
# [theme.templates.user.zsh]; Noctalia substitutes {{colors.<role>.default.hex}}
# on every palette change (compositor sessions) and writes the resolved output
# to ~/.zsh/themes/noctalia.zsh, which ~/.zshrc sources. This input is the only
# stowed half; the output is seed-only/gitignored (ADR 0128/0129 pattern).
#
# FZF_DEFAULT_OPTS MUST stay on one line: Noctalia's template engine fails to
# render a template that uses backslash line-continuations (VM-verified).

# ── fzf: accent = Material primary; base = surface_container_lowest ───────────
export FZF_DEFAULT_OPTS="--color=bg+:{{colors.surface_container.default.hex}},bg:{{colors.surface_container_lowest.default.hex}},spinner:{{colors.primary.default.hex}},hl:{{colors.primary.default.hex}},fg:{{colors.on_surface.default.hex}},header:{{colors.primary.default.hex}},info:{{colors.primary.default.hex}},pointer:{{colors.primary.default.hex}},marker:{{colors.terminal_normal_green.default.hex}},fg+:{{colors.on_surface.default.hex}},prompt:{{colors.primary.default.hex}},hl+:{{colors.primary.default.hex}}"

# ── zsh-syntax-highlighting: Material roles → highlighter styles ──────────────
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main cursor)
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[comment]='fg={{colors.outline.default.hex}}'
ZSH_HIGHLIGHT_STYLES[command]='fg={{colors.primary.default.hex}}'
ZSH_HIGHLIGHT_STYLES[builtin]='fg={{colors.primary.default.hex}}'
ZSH_HIGHLIGHT_STYLES[function]='fg={{colors.primary.default.hex}}'
ZSH_HIGHLIGHT_STYLES[alias]='fg={{colors.terminal_normal_green.default.hex}}'
ZSH_HIGHLIGHT_STYLES[precommand]='fg={{colors.terminal_normal_green.default.hex}},italic'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg={{colors.tertiary.default.hex}}'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg={{colors.tertiary.default.hex}}'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg={{colors.terminal_normal_yellow.default.hex}}'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg={{colors.terminal_normal_yellow.default.hex}}'
ZSH_HIGHLIGHT_STYLES[path]='fg={{colors.on_surface.default.hex}},underline'
ZSH_HIGHLIGHT_STYLES[globbing]='fg={{colors.secondary.default.hex}}'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg={{colors.error.default.hex}},bold'
