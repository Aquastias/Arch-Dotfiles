#!/usr/bin/env bats
# system/yazi program — ANSI-16 palette-following (ADR 0132). Static seam like
# kitty-program.bats / zsh-program.bats: assert the COMMITTED program
# definition, payload, package move, and byte-identical drift without running an
# install.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."       # .installer/tests/config → repo root
  PROG="$REPO/.installer/programs/system/yazi"
  CFG="$PROG/config.jsonc"
  INSTALL="$PROG/install.sh"
  HOMESEED="$PROG/home"
  YAZI="$REPO/.config/yazi"
  CORE="$REPO/.installer/hosts/core/profile.jsonc"
  UCORE="$REPO/.installer/users/core/profile.jsonc"
}

# ── program definition ───────────────────────────────────────────────────────

@test "system/yazi config.jsonc declares the user-kind yazi program" {
  [ -f "$CFG" ]
  grep -q '"name": "yazi"' "$CFG"
  grep -q '"kind": "user"' "$CFG"
}

@test "install.sh has the mandated shape and installs yazi" {
  [ -f "$INSTALL" ]
  # set -Eeuo pipefail + trap are the first two non-comment lines (PROGRAM_SPEC)
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$INSTALL' | head -2"
  [[ "${lines[0]}" == "set -Eeuo pipefail" ]]
  [[ "${lines[1]}" == trap* ]]
  # the program owns the yazi package (exclusivity, ADR 0115)
  grep -q '${AUR_HELPER} -S --noconfirm --needed yazi' "$INSTALL"
  grep -q 'print_status success' "$INSTALL"
  ! grep -qE 'systemctl (start|restart)' "$INSTALL"
}

@test "install.sh does NOT seed home/ theme — the pass applies it (ADR 0134)" {
  ! grep -q 'cp -a "${SELF}/home/." "${HOME}/"' "$INSTALL"
  ! grep -q 'cp -a "${SELF}/home/." /etc/skel/' "$INSTALL"
  ! grep -q 'cp -a "${SELF}/home/." /root/' "$INSTALL"
}

@test "home/ is the single source: no repo-root .config/yazi duplicate" {
  [ -d "$HOMESEED" ]
  [ -f "$HOMESEED/.config/yazi/theme.toml" ]
  [ ! -e "$YAZI" ]   # ADR 0134: repo-root stow-tree copy retired
}

# ── ANSI-16 theming: named colors only, current [mgr] schema (ADR 0132) ──────

@test "yazi theme is named ANSI colors only — no hex, current [mgr] table" {
  thm="$HOMESEED/.config/yazi/theme.toml"
  ! grep -qE '#[0-9a-fA-F]{6}' "$thm"
  grep -q '^\[mgr\]' "$thm"          # current table name, not [manager]
  grep -qE 'fg = "(blue|red|green|yellow|cyan|black|white|reset)"' "$thm"
}

# ── package move: exclusivity (ADR 0115) ─────────────────────────────────────

@test "yazi left core packages.shell (Program/package exclusivity)" {
  ! grep -q '"yazi"' "$CORE"
}

# ── profile wiring ───────────────────────────────────────────────────────────

@test "User Core serves the yazi program fleet-wide" {
  grep -qE '"yazi"' "$UCORE"
}
