#!/usr/bin/env bats
# Tests for lib/boot/boot-recovery.sh — interrupted-update recovery (ADR 0166).
#
# Sourced lib-only (BOOT_RECOVERY_LIB_ONLY=1) so the hook runtimes are skipped.
# Every decision reads a fixture tree (power-supply class dir, modules dir,
# stash dir), never the live system.

setup() {
  BOOT_RECOVERY_LIB_ONLY=1
  # shellcheck source=../../lib/boot/boot-recovery.sh
  source "$BATS_TEST_DIRNAME/../../lib/boot/boot-recovery.sh"
  FIXTURE="$(mktemp -d)"
  SUPPLY="$FIXTURE/power_supply"
  mkdir -p "$SUPPLY"
}

teardown() { rm -rf "$FIXTURE"; }

# _battery <name> <status> <capacity>
_battery() {
  mkdir -p "$SUPPLY/$1"
  echo Battery >"$SUPPLY/$1/type"
  echo "$2" >"$SUPPLY/$1/status"
  echo "$3" >"$SUPPLY/$1/capacity"
}

# _mains <name> <online>
_mains() {
  mkdir -p "$SUPPLY/$1"
  echo Mains >"$SUPPLY/$1/type"
  echo "$2" >"$SUPPLY/$1/online"
}

@test "battery_ok: no battery (desktop) allows the update" {
  _mains ucsi-source-psy-0 0
  run boot_recovery_battery_ok "$SUPPLY"
  [ "$status" -eq 0 ]
}

@test "battery_ok: discharging below 30% refuses" {
  _battery BAT0 Discharging 29
  _mains AC 0
  run boot_recovery_battery_ok "$SUPPLY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"29%"* ]]
}

@test "battery_ok: discharging at 30% allows" {
  _battery BAT0 Discharging 30
  run boot_recovery_battery_ok "$SUPPLY"
  [ "$status" -eq 0 ]
}

@test "battery_ok: low battery but charging allows" {
  _battery BAT0 Charging 5
  run boot_recovery_battery_ok "$SUPPLY"
  [ "$status" -eq 0 ]
}

@test "battery_ok: low battery with the charger online allows" {
  _battery BAT0 "Not charging" 5
  _mains AC 1
  run boot_recovery_battery_ok "$SUPPLY"
  [ "$status" -eq 0 ]
}

@test "battery_ok: two batteries average their capacity" {
  _battery BAT0 Discharging 10
  _battery BAT1 Discharging 60
  run boot_recovery_battery_ok "$SUPPLY"
  [ "$status" -eq 0 ]
}

@test "battery hook: kernel-path PreTransaction that aborts the transaction" {
  run boot_recovery_battery_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Target = usr/lib/modules/*/vmlinuz"* ]]
  [[ "$output" == *"When = PreTransaction"* ]]
  [[ "$output" == *"Exec = /usr/local/lib/archzfs/boot-recovery.sh battery"* ]]
  [[ "$output" == *"AbortOnFail"* ]]
}
