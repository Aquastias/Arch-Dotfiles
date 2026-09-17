#!/usr/bin/env bats
# system/lazygit program — ANSI-16 palette-following (ADR 0132). Static seam
# like kitty-program.bats / zsh-program.bats: assert the COMMITTED program
# definition, payload, package move, and byte-identical drift without running an
# install.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."       # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/system/lazygit"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  HOMESEED="$PROG/home"
  LZG="$REPO/.config/lazygit"
  CORE="$REPO/.installer/hosts/core/profile.jsonc"
  UCORE="$REPO/.installer/users/core/profile.jsonc"
}

# ── program definition ───────────────────────────────────────────────────────

@test "system/lazygit config.jsonc declares the user-kind lazygit program" {
  [ -f "$CFG" ]
  grep -q '"name": "lazygit"' "$CFG"
  grep -q '"kind": "user"' "$CFG"
}

@test "install.sh has the mandated shape and installs lazygit" {
  [ -f "$INSTALL" ]
  # set -Eeuo pipefail + trap are the first two non-comment lines (PROGRAM_SPEC)
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$INSTALL' | head -2"
  [[ "${lines[0]}" == "set -Eeuo pipefail" ]]
  [[ "${lines[1]}" == trap* ]]
  # the program owns the lazygit package (exclusivity, ADR 0115)
  grep -q '${AUR_HELPER} -S --noconfirm --needed lazygit' "$INSTALL"
  grep -q 'print_status success' "$INSTALL"
  ! grep -qE 'systemctl (start|restart)' "$INSTALL"
}

@test "install.sh does NOT seed home/ config — the pass applies it (ADR 0134)" {
  ! grep -q 'cp -a "${SELF}/home/." "${HOME}/"' "$INSTALL"
  ! grep -q 'cp -a "${SELF}/home/." /etc/skel/' "$INSTALL"
  ! grep -q 'cp -a "${SELF}/home/." /root/' "$INSTALL"
}

@test "home/ is the single source: no repo-root .config/lazygit duplicate" {
  [ -d "$HOMESEED" ]
  [ -f "$HOMESEED/.config/lazygit/config.yml" ]
  [ ! -e "$LZG" ]   # ADR 0134: repo-root stow-tree copy retired
}

# ── ANSI-16 theming: no hardcoded hex (ADR 0132) ─────────────────────────────

@test "lazygit theme is ANSI names only — no hex color" {
  cfg="$HOMESEED/.config/lazygit/config.yml"
  ! grep -qE '#[0-9a-fA-F]{6}' "$cfg"
  grep -q 'activeBorderColor' "$cfg"
  grep -qE '^[[:space:]]*-[[:space:]]*(blue|red|green|yellow|cyan|default)' \
    "$cfg"
}

# ── package move: exclusivity (ADR 0115) ─────────────────────────────────────

@test "lazygit left core packages.shell (Program/package exclusivity)" {
  ! grep -q '"lazygit"' "$CORE"
}

# ── profile wiring ───────────────────────────────────────────────────────────

@test "User Core serves the lazygit program fleet-wide" {
  grep -qE '"lazygit"' "$UCORE"
}
