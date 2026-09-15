#!/usr/bin/env bats
# ANSI-16 cohesion guardrails for the already-cohesive tools (ADR 0132, issue
# 05). htop follows the palette via color_scheme=0 for free and its htoprc is
# runtime-rewritten, so it must never be stowed; git/less/ripgrep/fd render
# default ANSI; neovim is out of scope (rose-pine intact).

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

@test "neovim is out of scope: its rose-pine colorscheme is untouched" {
  grep -q 'rose-pine' "$REPO/.config/nvim/lua/colorscheme.lua"
}
