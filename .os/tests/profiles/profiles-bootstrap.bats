#!/usr/bin/env bats
# The AUR-helper bootstrap ladder + Runner AUR pass (ADR 0052), in
# lib/profiles/runner.sh. The chroot-executing rung (_profiles_bootstrap_rung)
# and the chroot helper probe (_profiles_detect_user_helper) are stubbed, so
# these assert the pure orchestration: rung ordering, which helper the winning
# rung resolves to, all-rungs-fail abort, the skip path, and the paru-only
# pre-flight gate. No paru, no arch-chroot.

setup() {
  T="$(mktemp -d)"
  export MOUNT_ROOT=/mnt

  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/categorized-list.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"

  # Never wait during retry backoff.
  sleep() { :; }
}

teardown() { rm -rf "$T"; }

# ── ladder ordering + resolved helper name ──────────────────────────────────

@test "ladder: rung 1 (paru source) wins → resolves paru" {
  _profiles_detect_user_helper() { return 1; }        # nothing installed yet
  _profiles_bootstrap_rung() { [[ "$2" == paru ]]; }  # only paru succeeds
  local h st
  h="$(_profiles_bootstrap_helper alice 2>/dev/null)"; st=$?
  [ "$st" -eq 0 ]
  [ "$h" = paru ]
}

@test "ladder: paru fails, paru-bin wins → resolves paru" {
  _profiles_detect_user_helper() { return 1; }
  _profiles_bootstrap_rung() { [[ "$2" == paru-bin ]]; }
  local h st
  h="$(_profiles_bootstrap_helper alice 2>/dev/null)"; st=$?
  [ "$st" -eq 0 ]
  [ "$h" = paru ]
}

@test "ladder: only yay-bin succeeds → resolves yay" {
  _profiles_detect_user_helper() { return 1; }
  _profiles_bootstrap_rung() { [[ "$2" == yay-bin ]]; }
  local h st
  h="$(_profiles_bootstrap_helper alice 2>/dev/null)"; st=$?
  [ "$st" -eq 0 ]
  [ "$h" = yay ]
}

@test "ladder: all rungs fail → aborts non-zero" {
  _profiles_detect_user_helper() { return 1; }
  _profiles_bootstrap_rung() { return 1; }   # every rung fails
  # error() exits 1; `run` captures it (repo idiom, cf. profiles-aur.bats).
  run _profiles_bootstrap_helper alice
  [ "$status" -ne 0 ]
}

@test "ladder: tries rungs in order paru → paru-bin → yay-bin" {
  _profiles_detect_user_helper() { return 1; }
  _profiles_bootstrap_rung() { printf '%s\n' "$2" >> "$T/order"; return 1; }
  run _profiles_bootstrap_helper alice
  # Each rung retried 3x; collapse to first-seen order.
  [ "$(awk '!seen[$0]++' "$T/order" | paste -sd, -)" = "paru,paru-bin,yay-bin" ]
}

@test "ladder: skips bootstrap when a helper already exists" {
  _profiles_detect_user_helper() { echo paru; }   # already installed
  _profiles_bootstrap_rung() { echo ran >> "$T/rung"; return 0; }
  local h st
  h="$(_profiles_bootstrap_helper alice 2>/dev/null)"; st=$?
  [ "$st" -eq 0 ]
  [ "$h" = paru ]
  [ ! -f "$T/rung" ]           # no rung executed
}

# ── AUR pass pre-flight gate ────────────────────────────────────────────────

@test "aur_install: paru runs the pre-flight then the real install" {
  : > "$T/calls"
  arch-chroot() { echo "$*" >> "$T/calls"; }
  _profiles_aur_install alice paru pkg1 pkg2
  grep -q -- "-Sp" "$T/calls"                          # pre-flight ran
  grep -q "paru -S --noconfirm --needed pkg1 pkg2" "$T/calls"
}

@test "aur_install: yay skips the pre-flight, installs directly" {
  : > "$T/calls"
  arch-chroot() { echo "$*" >> "$T/calls"; }
  _profiles_aur_install alice yay pkg1
  ! grep -q -- "-Sp" "$T/calls"                        # no pre-flight
  grep -q "yay -S --noconfirm --needed pkg1" "$T/calls"
}
