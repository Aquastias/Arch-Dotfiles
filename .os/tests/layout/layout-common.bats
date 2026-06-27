#!/usr/bin/env bats
# Tests for .os/lib/layout/zfs/common.sh — parse_size_to_gib and
# layout_resolve_esp_size.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  # shellcheck source=../../lib/layout/zfs/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/zfs/common.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_config() {
  printf '%s\n' "$1" > "$CONFIG_FILE"
}

# ── parse_size_to_gib ─────────────────────────────────────────────────────────

@test "parse_size_to_gib: 512M → 1 GiB (rounded up)" {
  run parse_size_to_gib 512M
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "parse_size_to_gib: 1024M → 1 GiB (exact)" {
  run parse_size_to_gib 1024M
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "parse_size_to_gib: 1025M → 2 GiB (rounds up)" {
  run parse_size_to_gib 1025M
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "parse_size_to_gib: 80G → 80 GiB" {
  run parse_size_to_gib 80G
  [ "$status" -eq 0 ]
  [ "$output" -eq 80 ]
}

@test "parse_size_to_gib: 2T → 2048 GiB" {
  run parse_size_to_gib 2T
  [ "$status" -eq 0 ]
  [ "$output" -eq 2048 ]
}

@test "parse_size_to_gib: lowercase unit is accepted (512m)" {
  run parse_size_to_gib 512m
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "parse_size_to_gib: MiB suffix is accepted (512MiB)" {
  run parse_size_to_gib 512MiB
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "parse_size_to_gib: GiB suffix is accepted (10GiB)" {
  run parse_size_to_gib 10GiB
  [ "$status" -eq 0 ]
  [ "$output" -eq 10 ]
}

@test "parse_size_to_gib: unknown unit exits non-zero" {
  run parse_size_to_gib 100K
  [ "$status" -ne 0 ]
}

# ── parse_size_to_mib ─────────────────────────────────────────────────────────
# MiB precision (no rounding) — the ESP floor needs to tell 512M from 1G, which
# parse_size_to_gib cannot (it rounds 512M up to 1 GiB).

@test "parse_size_to_mib: 512M → 512" {
  run parse_size_to_mib 512M
  [ "$status" -eq 0 ]
  [ "$output" -eq 512 ]
}

@test "parse_size_to_mib: 1G → 1024" {
  run parse_size_to_mib 1G
  [ "$status" -eq 0 ]
  [ "$output" -eq 1024 ]
}

@test "parse_size_to_mib: 2G → 2048" {
  run parse_size_to_mib 2G
  [ "$status" -eq 0 ]
  [ "$output" -eq 2048 ]
}

# ── layout_resolve_esp_size ───────────────────────────────────────────────────

@test "layout_resolve_esp_size: returns configured esp_size" {
  write_config '{"options": {"esp_size": "1G"}}'
  run layout_resolve_esp_size
  [ "$status" -eq 0 ]
  [ "$output" = "1G" ]
}

@test "layout_resolve_esp_size: defaults to 2G when not configured" {
  write_config '{}'
  run layout_resolve_esp_size
  [ "$status" -eq 0 ]
  [ "$output" = "2G" ]
}

# ── layout_validate_esp_size (1G floor) ───────────────────────────────────────

@test "layout_validate_esp_size: passes for the 2G default" {
  write_config '{"options": {"esp_size": "2G"}}'
  run layout_validate_esp_size
  [ "$status" -eq 0 ]
}

@test "layout_validate_esp_size: passes at the 1G floor" {
  write_config '{"options": {"esp_size": "1G"}}'
  run layout_validate_esp_size
  [ "$status" -eq 0 ]
}

@test "layout_validate_esp_size: errors below 1G (512M), naming the field" {
  write_config '{"options": {"esp_size": "512M"}}'
  run layout_validate_esp_size
  [ "$status" -ne 0 ]
  [[ "$output" == *esp_size* ]]
}

@test "layout_validate_esp_size: errors below 1G (800M)" {
  write_config '{"options": {"esp_size": "800M"}}'
  run layout_validate_esp_size
  [ "$status" -ne 0 ]
}

# ── phase lifecycle helpers ───────────────────────────────────────────────────
# Phase ordinals: validate=1, plan=2, partition=3, pools=4, esp=5.
# _LAYOUT_PHASE is seeded to 0; tests below set it to 1 to simulate the
# validate phase having run, so the first callable phase under test is `plan`.

@test "_layout_enter_phase plan: succeeds from fresh state" {
  _LAYOUT_PHASE=1
  run _layout_enter_phase plan
  [ "$status" -eq 0 ]
}

@test "_layout_enter_phase partition: from fresh state errors out-of-order" {
  _LAYOUT_PHASE=1
  run _layout_enter_phase partition
  [ "$status" -ne 0 ]
  [[ "$output" == *"out of order"* ]]
}

@test "_layout_enter_phase plan: errors when called twice in a row" {
  _LAYOUT_PHASE=1
  _layout_enter_phase plan
  _layout_exit_phase plan
  run _layout_enter_phase plan
  [ "$status" -ne 0 ]
  [[ "$output" == *"out of order"* ]]
}

@test "phase walk plan→partition→pools→esp leaves _LAYOUT_PHASE=5" {
  _LAYOUT_PHASE=1
  _layout_enter_phase plan;      _layout_exit_phase plan
  _layout_enter_phase partition; _layout_exit_phase partition
  _layout_enter_phase pools;     _layout_exit_phase pools
  _layout_enter_phase esp;       _layout_exit_phase esp
  [ "$_LAYOUT_PHASE" -eq 5 ]
}

@test "_layout_phase_ordinal: unknown phase name errors" {
  run _layout_phase_ordinal bogus
  [ "$status" -ne 0 ]
}
