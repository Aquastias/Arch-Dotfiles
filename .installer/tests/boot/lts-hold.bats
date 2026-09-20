#!/usr/bin/env bats
# Tests for lib/boot/lts-hold.sh — the ongoing archzfs LTS ceiling hold (ADR
# 0139). Sourced lib-only (LTS_HOLD_LIB_ONLY=1) so the runtime is skipped; we
# assert the pure IgnorePkg editor over a temp pacman.conf.

setup() {
  LTS_HOLD_LIB_ONLY=1
  # shellcheck source=../../lib/boot/lts-hold.sh
  source "$BATS_TEST_DIRNAME/../../lib/boot/lts-hold.sh"
  CONF="$(mktemp)"
  printf '[options]\nHoldPkg = pacman glibc\n\n[core]\nInclude = /x\n' > "$CONF"
}

teardown() { rm -f "$CONF"; }

@test "hold=1 adds a marked IgnorePkg line inside [options]" {
  lts_hold_set "$CONF" 1
  grep -q '^IgnorePkg = linux-lts linux-lts-headers  # archzfs-lts-hold$' "$CONF"
  # placed within [options], before [core]
  local opt core
  opt=$(grep -n '^\[options\]' "$CONF" | cut -d: -f1)
  core=$(grep -n '^\[core\]' "$CONF" | cut -d: -f1)
  local ign; ign=$(grep -n 'archzfs-lts-hold' "$CONF" | cut -d: -f1)
  [ "$opt" -lt "$ign" ]; [ "$ign" -lt "$core" ]
}

@test "hold=0 removes the marked line, leaves the rest" {
  lts_hold_set "$CONF" 1
  lts_hold_set "$CONF" 0
  ! grep -q 'archzfs-lts-hold' "$CONF"
  grep -q '^HoldPkg = pacman glibc$' "$CONF"   # operator's own line intact
  grep -q '^\[core\]' "$CONF"
}

@test "hold is idempotent — repeated set=1 keeps exactly one marked line" {
  lts_hold_set "$CONF" 1
  lts_hold_set "$CONF" 1
  [ "$(grep -c 'archzfs-lts-hold' "$CONF")" -eq 1 ]
}

@test "hold never touches an operator's own IgnorePkg line" {
  printf '[options]\nIgnorePkg = mynvidia\n' > "$CONF"
  lts_hold_set "$CONF" 1
  lts_hold_set "$CONF" 0
  grep -q '^IgnorePkg = mynvidia$' "$CONF"     # survived both toggles
  ! grep -q 'archzfs-lts-hold' "$CONF"
}
