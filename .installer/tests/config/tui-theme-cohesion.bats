#!/usr/bin/env bats
# ANSI-16 cohesion guardrails for the already-cohesive tools (ADR 0132, issue
# 05). htop follows the palette via color_scheme=0 for free and its htoprc is
# runtime-rewritten, so it must never be stowed; git/less/ripgrep/fd render
# default ANSI; neovim now follows via its own template (ADR 0136), not ANSI-16.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."       # .installer/tests/config → repo root
}

@test "htoprc is never stowed (htop runtime-rewrites it — ADR 0132/0104)" {
  # A stowed htoprc would be clobbered by htop on clean exit and dirty the repo,
  # the same generated-file ban as the Noctalia template outputs. htop's Default
  # scheme already follows the terminal ANSI palette, so no file is shipped.
  [ ! -e "$REPO/.config/htop/htoprc" ]
}

@test "bat renders via the terminal ANSI palette (BAT_THEME=ansi)" {
  grep -q 'export BAT_THEME="ansi"' "$REPO/.zsh/env/exports.zsh"
}

@test "neovim follows via its own template now, not rose-pine (ADR 0136)" {
  # ADR 0136 amended ADR 0132: nvim is no longer excluded/rose-pine. It has its
  # own Neovim Theme Template (default off, static Catppuccin Mocha Sapphire),
  # served from the dev/nvim program — no repo-root .config/nvim remains.
  local CS="$REPO/.installer/programs/dev/nvim/home/.config/nvim/lua/plugins"
  [ ! -e "$REPO/.config/nvim" ]
  grep -rq 'catppuccin' "$CS"
}
