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

# ── Module Stash / Stash Restore ─────────────────────────────────────────────

# _kernel <version> <pkgbase> — fake an installed kernel's module tree.
_kernel() {
  mkdir -p "$FIXTURE/modules/$1/kernel"
  printf '%s\n' "$2" >"$FIXTURE/modules/$1/pkgbase"
  echo "ko-$1" >"$FIXTURE/modules/$1/kernel/vfat.ko"
}

@test "stash_plan: every installed selected kernel, never a stray" {
  _kernel 6.18.40-1-lts linux-lts
  _kernel 7.0.1-arch1-1 linux
  _kernel 6.19.2-zen1-1-zen linux-zen
  run boot_recovery_stash_plan "$FIXTURE/modules" linux-lts linux-zen
  [ "$status" -eq 0 ]
  [ "$output" = $'6.18.40-1-lts\n6.19.2-zen1-1-zen' ]
}

@test "stash: modules survive their removal, replacing an older stash" {
  _kernel 6.18.40-1-lts linux-lts
  mkdir -p "$FIXTURE/modules/.stash/6.0.0-old"
  boot_recovery_stash "$FIXTURE/modules" linux-lts
  rm -rf "$FIXTURE/modules/6.18.40-1-lts"
  [ "$(cat "$FIXTURE/modules/.stash/6.18.40-1-lts/kernel/vfat.ko")" \
    = ko-6.18.40-1-lts ]
  [ ! -e "$FIXTURE/modules/.stash/6.0.0-old" ]
}

@test "should_restore: only when the running kernel's modules are gone" {
  _kernel 6.18.60-1-lts linux-lts
  mkdir -p "$FIXTURE/modules/.stash/6.18.40-1-lts"
  run boot_recovery_should_restore "$FIXTURE/modules" 6.18.40-1-lts
  [ "$status" -eq 0 ]
  run boot_recovery_should_restore "$FIXTURE/modules" 6.18.60-1-lts
  [ "$status" -ne 0 ]
}

@test "should_restore: nothing to do without a stash" {
  run boot_recovery_should_restore "$FIXTURE/modules" 6.18.40-1-lts
  [ "$status" -ne 0 ]
}

@test "restore: puts the stash back and records it" {
  _kernel 6.18.40-1-lts linux-lts
  boot_recovery_stash "$FIXTURE/modules" linux-lts
  rm -rf "$FIXTURE/modules/6.18.40-1-lts"
  boot_recovery_restore "$FIXTURE/modules" 6.18.40-1-lts
  [ "$(cat "$FIXTURE/modules/6.18.40-1-lts/kernel/vfat.ko")" \
    = ko-6.18.40-1-lts ]
  [ "$(cat "$FIXTURE/modules/.stash/restored")" = "6.18.40-1-lts linux-lts" ]
}

@test "drop_stash: removes the stash and restored trees no package owns" {
  _kernel 6.18.40-1-lts linux-lts
  _kernel 6.18.30-1-lts linux-lts
  boot_recovery_stash "$FIXTURE/modules" linux-lts
  printf '%s\n' "6.18.40-1-lts linux-lts" "6.18.30-1-lts linux-lts" \
    >"$FIXTURE/modules/.stash/restored"
  # 6.18.30 was reinstalled by a package since; 6.18.40 is a leftover.
  boot_recovery_owned() { [[ "$1" == */6.18.30-1-lts/vmlinuz ]]; }
  boot_recovery_drop_stash "$FIXTURE/modules"
  [ ! -e "$FIXTURE/modules/.stash" ]
  [ ! -e "$FIXTURE/modules/6.18.40-1-lts" ]
  [ -d "$FIXTURE/modules/6.18.30-1-lts" ]
}

@test "stash hook: kernel paths, PreTransaction, before the dkms hooks" {
  run boot_recovery_stash_hook
  [[ "$output" == *"Target = usr/lib/modules/*/vmlinuz"* ]]
  [[ "$output" == *"When = PreTransaction"* ]]
  [[ "$output" == *"boot-recovery.sh stash"* ]]
  [[ "$output" == *"Operation = Remove"* ]]
}

@test "restore unit: before any module loads, only when modules are missing" {
  run boot_recovery_restore_unit
  [[ "$output" == *"DefaultDependencies=no"* ]]
  [[ "$output" == *"Before="*"systemd-modules-load.service"* ]]
  [[ "$output" == *"Before="*"systemd-udevd.service"* ]]
  [[ "$output" == *"ConditionPathExists=!/usr/lib/modules/%v"* ]]
  [[ "$output" == *"ConditionPathExists=/usr/lib/modules/.stash/%v"* ]]
  [[ "$output" == *"boot-recovery.sh restore"* ]]
}

@test "stash: a new stash keeps the restored record for drop_stash" {
  _kernel 6.18.40-1-lts linux-lts
  mkdir -p "$FIXTURE/modules/.stash"
  echo "6.18.40-1-lts linux-lts" >"$FIXTURE/modules/.stash/restored"
  boot_recovery_stash "$FIXTURE/modules" linux-lts
  [ "$(cat "$FIXTURE/modules/.stash/restored")" = "6.18.40-1-lts linux-lts" ]
}

@test "install: helper, hooks and the enabled restore unit under a root" {
  local root="$FIXTURE/root"
  boot_recovery_install "$root" \
    "$BATS_TEST_DIRNAME/../../lib/boot/boot-recovery.sh"
  [ -x "$root/usr/local/lib/archzfs/boot-recovery.sh" ]
  grep -q "boot-recovery.sh battery" \
    "$root/etc/pacman.d/hooks/92-battery-preflight.hook"
  grep -q "boot-recovery.sh stash" \
    "$root/etc/pacman.d/hooks/05-module-stash.hook"
  local units="$root/usr/lib/systemd/system"
  grep -q "boot-recovery.sh restore" "$units/boot-recovery-restore.service"
  # enabled from the vendor dir: /etc is rolled back on Impermanence hosts
  [ "$(readlink "$units/sysinit.target.wants/boot-recovery-restore.service")" \
    = ../boot-recovery-restore.service ]
}
