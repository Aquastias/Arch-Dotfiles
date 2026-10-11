# nvim-program-helpers.bash — shared setup for the nvim-program-*.bats parts
# dev/nvim program + hand-rolled Neovim Config (ADR 0135). Static seam like
# kitty-program.bats / pi-agent.bats: assert the COMMITTED program definition,
# single-source home/ config, and the static Catppuccin Mocha Sapphire default
# — no install run. Config is decoupled from install (ADR 0134): the Runner's
# Config Apply pass copies home/, so install.sh installs packages only.
# Grows per ticket: the LSP/formatter toolchain packages (02/03); the Neovim
# Theme Template live-follow wiring is asserted in noctalia-stow-*.bats (07).

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."        # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/dev/nvim"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  HOMESEED="$PROG/home"
  NVIM="$HOMESEED/.config/nvim"             # single source (ADR 0134)
  UCORE="$REPO/.installer/users/core/profile.jsonc"
}

