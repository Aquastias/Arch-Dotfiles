#!/usr/bin/env bats
# Tests for .os/lib/config/power.sh — the Power Profile resolver (ADR 0080): a
# pure helper turning options.power.profile into a toggle-derived System Program
# (power-profiles-daemon or tuned; none derives nothing), the injector that
# folds it into an Effective Config's host_programs, and the owned set the
# Packages picker filters.
#
# Behaviour under test is external only. Prior art: tests/config/printing.bats.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error
  # shellcheck source=../../lib/config/power.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/power.sh"
}

# ── power_profile: default ppd; explicit wins ───────────────────────────────

@test "power_profile: absent defaults to power-profiles-daemon" {
  [ "$(power_profile '{}')" = "power-profiles-daemon" ]
  [ "$(power_profile '{"options":{}}')" = "power-profiles-daemon" ]
}

@test "power_profile: explicit tuned and none are honoured" {
  [ "$(power_profile '{"options":{"power":{"profile":"tuned"}}}')" = "tuned" ]
  [ "$(power_profile '{"options":{"power":{"profile":"none"}}}')" = "none" ]
}

# ── power_programs: value → program; none derives nothing ───────────────────

@test "power_programs: default yields power-profiles-daemon" {
  run power_programs '{}'
  [ "$status" -eq 0 ]
  [ "$output" = "power-profiles-daemon" ]
}

@test "power_programs: tuned yields tuned" {
  run power_programs '{"options":{"power":{"profile":"tuned"}}}'
  [ "$output" = "tuned" ]
}

@test "power_programs: none yields nothing" {
  run power_programs '{"options":{"power":{"profile":"none"}}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── power_inject: folds the derived program in when not none ────────────────

@test "power_inject: default appends power-profiles-daemon, preserving existing" {
  run power_inject '{"host_programs":["grub"]}'
  echo "$output" | jq -e '.host_programs == ["grub","power-profiles-daemon"]'
}

@test "power_inject: tuned appends tuned" {
  run power_inject '{"host_programs":["grub"],
                     "options":{"power":{"profile":"tuned"}}}'
  echo "$output" | jq -e '.host_programs == ["grub","tuned"]'
}

@test "power_inject: none leaves a config without host_programs untouched" {
  run power_inject '{"options":{"power":{"profile":"none"}}}'
  echo "$output" | jq -e 'has("host_programs") | not'
}

@test "power_inject: idempotent when the daemon is already present" {
  run power_inject '{"host_programs":["power-profiles-daemon"]}'
  echo "$output" | jq -e '.host_programs == ["power-profiles-daemon"]'
}

# ── power_owned_programs: the picker-filter set ─────────────────────────────

@test "power_owned_programs: lists both backends regardless of state" {
  run power_owned_programs
  echo "$output" | grep -qx power-profiles-daemon
  echo "$output" | grep -qx tuned
}
