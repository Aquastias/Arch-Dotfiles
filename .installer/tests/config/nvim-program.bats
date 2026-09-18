#!/usr/bin/env bats
# dev/nvim program + hand-rolled Neovim Config (ADR 0135). Static seam like
# kitty-program.bats / pi-agent.bats: assert the COMMITTED program definition,
# single-source home/ config, and the static Catppuccin Mocha Sapphire default
# — no install run. Config is decoupled from install (ADR 0134): the Runner's
# Config Apply pass copies home/, so install.sh installs packages only.
# Grows per ticket: the LSP/formatter toolchain packages (02/03); the Neovim
# Theme Template live-follow wiring is asserted in noctalia-stow.bats (07).

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."        # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/dev/nvim"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  HOMESEED="$PROG/home"
  NVIM="$HOMESEED/.config/nvim"             # single source (ADR 0134)
  UCORE="$REPO/.installer/users/core/profile.jsonc"
}

# ── program definition ───────────────────────────────────────────────────────

@test "dev/nvim config.jsonc declares the user-kind nvim program" {
  [ -f "$CFG" ]
  grep -q '"name": "nvim"' "$CFG"
  grep -q '"kind": "user"' "$CFG"
}

@test "install.sh has the mandated shape and starts no service" {
  [ -f "$INSTALL" ]
  # set -Eeuo pipefail + trap are the first two non-comment lines (PROGRAM_SPEC)
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$INSTALL' | head -2"
  [[ "${lines[0]}" == "set -Eeuo pipefail" ]]
  [[ "${lines[1]}" == trap* ]]
  grep -q 'print_status success' "$INSTALL"
  ! grep -qE 'systemctl (start|restart)' "$INSTALL"
}

@test "install.sh does NOT seed home/ config — the pass applies it (ADR 0134)" {
  ! grep -q 'cp -a "${SELF}/home/." "${HOME}/"' "$INSTALL"
  ! grep -q 'cp -a "${SELF}/home/." /etc/skel/' "$INSTALL"
  ! grep -q 'cp -a "${SELF}/home/." /root/' "$INSTALL"
}

# ── single-source config (ADR 0134) ──────────────────────────────────────────

@test "home/ is the single source of the served config" {
  [ -d "$NVIM" ]
  [ -f "$NVIM/init.lua" ]
  [ -f "$NVIM/lua/config/lazy.lua" ]
  [ -f "$NVIM/lua/config/options.lua" ]
}

@test "config is hand-rolled on lazy.nvim, not the LazyVim distro (ADR 0135)" {
  grep -rq 'folke/lazy.nvim' "$NVIM/lua/config/lazy.lua"
  ! grep -rq 'LazyVim/LazyVim' "$NVIM"
  ! grep -rq 'import = "lazyvim' "$NVIM"
}

# ── static default look (ADR 0136) ───────────────────────────────────────────

@test "default look is Catppuccin Mocha with a sapphire accent (ADR 0136)" {
  # palette switching + the follow_noctalia live path arrive in tickets 06/07
  grep -rq 'catppuccin' "$NVIM/lua/plugins"
  grep -rq 'mocha' "$NVIM/lua/plugins"
  grep -rq '#74c7ec' "$NVIM/lua/plugins"    # Catppuccin sapphire accent
}

@test "follow_noctalia defaults to false (static out of the box, ADR 0136)" {
  grep -rqE 'follow_noctalia[[:space:]]*=[[:space:]]*false' "$NVIM/lua"
}

@test "unused language providers are disabled so checkhealth stays quiet" {
  grep -rq 'loaded_perl_provider' "$NVIM/lua/config"
  grep -rq 'loaded_ruby_provider' "$NVIM/lua/config"
  grep -rq 'loaded_node_provider' "$NVIM/lua/config"
}

# ── profile wiring ───────────────────────────────────────────────────────────

@test "User Core serves the nvim program fleet-wide" {
  grep -q '"nvim"' "$UCORE"
}
