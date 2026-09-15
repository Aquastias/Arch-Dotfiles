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

@test "install.sh seeds theme to \$HOME, /etc/skel, /root (ADR 0095)" {
  grep -q 'cp -a "${SELF}/home/." "${HOME}/"' "$INSTALL"
  grep -q 'sudo cp -a "${SELF}/home/." /etc/skel/' "$INSTALL"
  grep -q 'sudo cp -a "${SELF}/home/." /root/' "$INSTALL"
}

@test "bundled home/ theme is byte-identical to the repo stow tree (drift)" {
  [ -d "$HOMESEED" ]
  # no seed-only themes dir: the ANSI-16 theme is static (ADR 0132), so the
  # whole tree is checked with no exclusion (unlike kitty/zsh)
  diff -r "$YAZI" "$HOMESEED/.config/yazi"
}

# ── ANSI-16 theming: named colors only, current [mgr] schema (ADR 0132) ──────

@test "yazi theme is named ANSI colors only — no hex, current [mgr] table" {
  ! grep -qE '#[0-9a-fA-F]{6}' "$YAZI/theme.toml"
  grep -q '^\[mgr\]' "$YAZI/theme.toml"          # current table name, not [manager]
  grep -qE 'fg = "(blue|red|green|yellow|cyan|black|white|reset)"' \
    "$YAZI/theme.toml"
}

# ── package move: exclusivity (ADR 0115) ─────────────────────────────────────

@test "yazi left core packages.shell (Program/package exclusivity)" {
  ! grep -q '"yazi"' "$CORE"
}

# ── profile wiring ───────────────────────────────────────────────────────────

@test "User Core serves the yazi program fleet-wide" {
  grep -qE '"yazi"' "$UCORE"
}
