#!/usr/bin/env bats
# Tests for .installer/lib/config/bluetooth.sh — the Bluetooth Service resolver (ADR
# 0080): a pure helper turning options.bluetooth.enabled into the toggle-derived
# System Program (bluetooth when on, nothing when off), the injector that folds
# it into an Effective Config's host_programs, and the picker-filter owned set.
#
# Behaviour under test is external only. Prior art: tests/config/printing.bats.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error
  # shellcheck source=../../lib/config/bluetooth.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/bluetooth.sh"
}

# ── bluetooth_enabled: default on; explicit false off ───────────────────────

@test "bluetooth_enabled: absent toggle defaults on" {
  [ "$(bluetooth_enabled '{}')" = "true" ]
  [ "$(bluetooth_enabled '{"options":{}}')" = "true" ]
}

@test "bluetooth_enabled: explicit false is off" {
  local off='{"options":{"bluetooth":{"enabled":false}}}'
  [ "$(bluetooth_enabled "$off")" = "false" ]
}

# ── bluetooth_programs: bluetooth when on, nothing when off ──────────────────

@test "bluetooth_programs: absent toggle (default on) yields bluetooth" {
  run bluetooth_programs '{}'
  [ "$status" -eq 0 ]
  [ "$output" = "bluetooth" ]
}

@test "bluetooth_programs: off yields nothing" {
  run bluetooth_programs '{"options":{"bluetooth":{"enabled":false}}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── bluetooth_inject: folds bluetooth into host_programs when on ──────────

@test "bluetooth_inject: on appends bluetooth, preserving existing" {
  run bluetooth_inject '{"host_programs":["grub"],
                         "options":{"bluetooth":{"enabled":true}}}'
  echo "$output" | jq -e '.host_programs == ["grub","bluetooth"]'
}

@test "bluetooth_inject: default-on (absent toggle) still injects bluetooth" {
  run bluetooth_inject '{"host_programs":["grub"]}'
  echo "$output" | jq -e '.host_programs == ["grub","bluetooth"]'
}

@test "bluetooth_inject: idempotent when bluetooth already present" {
  run bluetooth_inject '{"host_programs":["bluetooth"]}'
  echo "$output" | jq -e '.host_programs == ["bluetooth"]'
}

@test "bluetooth_inject: off leaves a config without host_programs untouched" {
  run bluetooth_inject '{"options":{"bluetooth":{"enabled":false}}}'
  echo "$output" | jq -e 'has("host_programs") | not'
}

# ── bluetooth_owned_programs: the picker-filter set ─────────────────────────

@test "bluetooth_owned_programs: lists bluetooth" {
  run bluetooth_owned_programs
  [ "$output" = "bluetooth" ]
}
