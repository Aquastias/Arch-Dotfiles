#!/usr/bin/env bats
# Tests for .installer/lib/layout/zfs/common.sh — layout_parse_size_to_gib and
# layout_resolve_esp_size.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"
  # shellcheck source=../../lib/layout/zfs/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/zfs/common.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_config() {
  printf '%s\n' "$1" > "$CONFIG_FILE"
}

@test "size parsers read a leading zero as decimal, not octal" {
  # bash arithmetic read 010 as 8 and aborted on 08.
  run layout_parse_size_to_gib 010G
  [ "$output" = "10" ]
  run layout_parse_size_to_mib 08G
  [ "$status" -eq 0 ]
  [ "$output" = "8192" ]
}

@test "size parsers reject a unit with no number" {
  run layout_parse_size_to_mib G
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot parse size"* ]]
}

# ── layout_parse_size_to_gib ─────────────────────────────────────────────────────────

@test "layout_parse_size_to_gib: 512M → 1 GiB (rounded up)" {
  run layout_parse_size_to_gib 512M
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "layout_parse_size_to_gib: 1024M → 1 GiB (exact)" {
  run layout_parse_size_to_gib 1024M
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "layout_parse_size_to_gib: 1025M → 2 GiB (rounds up)" {
  run layout_parse_size_to_gib 1025M
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "layout_parse_size_to_gib: 80G → 80 GiB" {
  run layout_parse_size_to_gib 80G
  [ "$status" -eq 0 ]
  [ "$output" -eq 80 ]
}

@test "layout_parse_size_to_gib: 2T → 2048 GiB" {
  run layout_parse_size_to_gib 2T
  [ "$status" -eq 0 ]
  [ "$output" -eq 2048 ]
}

@test "layout_parse_size_to_gib: lowercase unit is accepted (512m)" {
  run layout_parse_size_to_gib 512m
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "layout_parse_size_to_gib: MiB suffix is accepted (512MiB)" {
  run layout_parse_size_to_gib 512MiB
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "layout_parse_size_to_gib: GiB suffix is accepted (10GiB)" {
  run layout_parse_size_to_gib 10GiB
  [ "$status" -eq 0 ]
  [ "$output" -eq 10 ]
}

@test "layout_parse_size_to_gib: unknown unit exits non-zero" {
  run layout_parse_size_to_gib 100K
  [ "$status" -ne 0 ]
}

# ── layout_parse_size_to_mib ─────────────────────────────────────────────────────────
# MiB precision (no rounding) — the ESP floor needs to tell 512M from 1G, which
# layout_parse_size_to_gib cannot (it rounds 512M up to 1 GiB).

@test "layout_parse_size_to_mib: 512M → 512" {
  run layout_parse_size_to_mib 512M
  [ "$status" -eq 0 ]
  [ "$output" -eq 512 ]
}

@test "layout_parse_size_to_mib: 1G → 1024" {
  run layout_parse_size_to_mib 1G
  [ "$status" -eq 0 ]
  [ "$output" -eq 1024 ]
}

@test "layout_parse_size_to_mib: 2G → 2048" {
  run layout_parse_size_to_mib 2G
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

@test "layout_resolve_esp_size: auto default resolves to 2G for 1 kernel" {
  write_config '{}'
  run layout_resolve_esp_size
  [ "$status" -eq 0 ]
  [ "$output" = "2G" ]
}

@test "layout_resolve_esp_size: auto grows past 2G for five kernels (0078)" {
  write_config '{"options":{"esp_size":"auto",
    "kernel":["lts","default","hardened","zen","lts"]}}'
  run layout_resolve_esp_size
  [ "$status" -eq 0 ]
  [ "$output" = "2304M" ]
}

@test "layout_resolve_esp_size: auto sizes grub like any loader (ADR 0078)" {
  write_config '{"filesystem":"zfs","options":{"esp_size":"auto",
    "bootloader":"grub","kernel":["lts","zen"]}}'
  run layout_resolve_esp_size
  [ "$status" -eq 0 ]
  [ "$output" = "2G" ]
}

@test "layout_validate_esp_size: pinned 1G too small for 4 kernels aborts" {
  write_config '{"filesystem":"zfs","options":{"esp_size":"1G",
    "kernel":["lts","default","hardened","zen"]}}'
  run layout_validate_esp_size
  [ "$status" -ne 0 ]
  [[ "$output" == *esp_size* ]]
  [[ "$output" == *auto* ]]
}

@test "layout_validate_esp_size: auto never triggers the budget guard" {
  write_config '{"filesystem":"zfs","options":{"esp_size":"auto",
    "kernel":["lts","default","hardened","zen"]}}'
  run layout_validate_esp_size
  [ "$status" -eq 0 ]
}

@test "layout_validate_esp_size: grub + auto clears the floor" {
  write_config '{"options":{"esp_size":"auto","bootloader":"grub"}}'
  run layout_validate_esp_size
  [ "$status" -eq 0 ]
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

@test "layout_enter_phase plan: succeeds from fresh state" {
  _LAYOUT_PHASE=1
  run layout_enter_phase plan
  [ "$status" -eq 0 ]
}

@test "layout_enter_phase partition: from fresh state errors out-of-order" {
  _LAYOUT_PHASE=1
  run layout_enter_phase partition
  [ "$status" -ne 0 ]
  [[ "$output" == *"out of order"* ]]
}

@test "layout_enter_phase plan: errors when called twice in a row" {
  _LAYOUT_PHASE=1
  layout_enter_phase plan
  layout_exit_phase plan
  run layout_enter_phase plan
  [ "$status" -ne 0 ]
  [[ "$output" == *"out of order"* ]]
}

@test "phase walk plan→partition→pools→esp leaves _LAYOUT_PHASE=5" {
  _LAYOUT_PHASE=1
  layout_enter_phase plan;      layout_exit_phase plan
  layout_enter_phase partition; layout_exit_phase partition
  layout_enter_phase pools;     layout_exit_phase pools
  layout_enter_phase esp;       layout_exit_phase esp
  [ "$_LAYOUT_PHASE" -eq 5 ]
}

@test "_core_phase_ordinal: unknown phase name errors" {
  run _core_phase_ordinal bogus
  [ "$status" -ne 0 ]
}
