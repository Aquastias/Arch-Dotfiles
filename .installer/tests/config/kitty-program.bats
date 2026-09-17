#!/usr/bin/env bats
# system/kitty program + Kitty Theme Template (ADR 0130). Static seam like
# zsh-program.bats / pi-agent.bats: assert the COMMITTED program definition,
# single-source home/ config, and seed theme default without running an
# install. Config is decoupled from install (ADR 0134): the Runner's Config
# Apply pass copies home/, so install.sh installs the package only.
# The Noctalia live-follow wiring (config.toml, template input) is asserted in
# noctalia-stow.bats.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."       # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/system/kitty"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  HOMESEED="$PROG/home"
  SEED_THEME="$PROG/themes/noctalia.conf"
  KITTY="$HOMESEED/.config/kitty"          # single source (ADR 0134)
  UCORE="$REPO/.installer/users/core/profile.jsonc"
  GI="$REPO/.gitignore"
}

# ── program definition ───────────────────────────────────────────────────────

@test "system/kitty config.jsonc declares the user-kind kitty program" {
  [ -f "$CFG" ]
  grep -q '"name": "kitty"' "$CFG"
  grep -q '"kind": "user"' "$CFG"
}

@test "install.sh has the mandated shape and installs kitty + the font" {
  [ -f "$INSTALL" ]
  # set -Eeuo pipefail + trap are the first two non-comment lines (PROGRAM_SPEC)
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$INSTALL' | head -2"
  [[ "${lines[0]}" == "set -Eeuo pipefail" ]]
  [[ "${lines[1]}" == trap* ]]
  # the program owns the kitty package (exclusivity, ADR 0115) + the Nerd font
  grep -q '${AUR_HELPER} -S --noconfirm --needed kitty ttf-firacode-nerd' \
    "$INSTALL"
  grep -q 'print_status success' "$INSTALL"
  ! grep -qE 'systemctl (start|restart)' "$INSTALL"
}

@test "install.sh does NOT seed home/ config — the pass applies it (ADR 0134)" {
  # Config is decoupled from package install: install.sh installs the package,
  # the Runner's Config Apply pass copies home/. So no home/ cp lives here.
  ! grep -q 'cp -a "${SELF}/home/." "${HOME}/"' "$INSTALL"
  ! grep -q 'cp -a "${SELF}/home/." /etc/skel/' "$INSTALL"
  ! grep -q 'cp -a "${SELF}/home/." /root/' "$INSTALL"
}

@test "install.sh seeds the generated palette theme into all three targets" {
  grep -q '"${HOME}/.config/kitty/themes/noctalia.conf"' "$INSTALL"
  grep -q '/etc/skel/.config/kitty/themes/noctalia.conf' "$INSTALL"
  grep -q '/root/.config/kitty/themes/noctalia.conf' "$INSTALL"
}

@test "home/ is the single source: no repo-root .config/kitty duplicate" {
  [ -d "$HOMESEED" ]
  [ -f "$HOMESEED/.config/kitty/kitty.conf" ]
  # ADR 0134: the repo-root stow tree copy is gone — home/ is the one source.
  [ ! -e "$REPO/.config/kitty" ]
  # generated themes/ is seed-only, excluded from the bundle (as zsh does)
  [ ! -e "$HOMESEED/.config/kitty/themes" ]
}

@test "kitty config carries no invalid auto_reload_config (parse error)" {
  # kitty has NO auto_reload_config option; it auto-reloads config by default.
  # Setting it is a hard parse error (VM-verified, ADR 0130); never re-add.
  ! grep -rq 'auto_reload_config' "$KITTY"
}

# ── seed theme: Catppuccin Mocha Sapphire default (ADR 0109) ─────────────────

@test "seeded noctalia.conf is the Mocha Sapphire palette default" {
  [ -f "$SEED_THEME" ]
  grep -q '^background            #1e1e2e' "$SEED_THEME"   # Mocha base
  grep -q '^foreground            #cdd6f4' "$SEED_THEME"   # Mocha text
  grep -q '^active_border_color   #74c7ec' "$SEED_THEME"   # Sapphire accent
  grep -q '^active_tab_background   #74c7ec' "$SEED_THEME"
}

@test "generated theme is seed-only: gitignored, never in the stow tree" {
  grep -q '^\.config/kitty/themes/' "$GI"
  [ ! -e "$KITTY/themes/noctalia.conf" ]
}

# ── profile wiring ───────────────────────────────────────────────────────────

@test "User Core serves the kitty program fleet-wide, after zsh" {
  # programs is a multi-line array; assert both are listed (order: zsh precedes
  # kitty in the source), not that they share one line.
  grep -q '"zsh"' "$UCORE"
  grep -q '"kitty"' "$UCORE"
}
