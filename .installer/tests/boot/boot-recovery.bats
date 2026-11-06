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
  depmod() { :; }  # never the live module tree
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
  mkdir -p "$FIXTURE/modules/.stash/6.18.40-1-lts/kernel"
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
  # a pure removal never reaches the sync that drops the stash
  [[ "$output" != *"Operation = Remove"* ]]
}

@test "restore unit: before any module loads, only when modules are missing" {
  run boot_recovery_restore_unit
  [[ "$output" == *"DefaultDependencies=no"* ]]
  [[ "$output" == *"Before="*"systemd-modules-load.service"* ]]
  [[ "$output" == *"Before="*"systemd-udevd.service"* ]]
  [[ "$output" == *"ConditionPathExists=!/usr/lib/modules/%v/kernel"* ]]
  [[ "$output" == *"ConditionPathExists=/usr/lib/modules/.stash/%v/kernel"* ]]
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
    "$root/etc/pacman.d/hooks/00-battery-preflight.hook"
  grep -q "boot-recovery.sh stash" \
    "$root/etc/pacman.d/hooks/05-module-stash.hook"
  local units="$root/usr/lib/systemd/system"
  grep -q "boot-recovery.sh restore" "$units/boot-recovery-restore.service"
  # enabled from the vendor dir: /etc is rolled back on Impermanence hosts
  [ "$(readlink "$units/sysinit.target.wants/boot-recovery-restore.service")" \
    = ../boot-recovery-restore.service ]
}

# ── interruption notice ──────────────────────────────────────────────────────


@test "notice: silent when nothing was restored" {
  run boot_recovery_notice "$FIXTURE/modules"
  [ -z "$output" ]
}

@test "restore unit: prints to the console as well as the journal" {
  run boot_recovery_restore_unit
  [[ "$output" == *"StandardOutput=journal+console"* ]]
}

@test "notice unit: user unit, only while a restore is pending" {
  run boot_recovery_notice_unit
  [[ "$output" == *"ConditionPathExists=/usr/lib/modules/.stash/restored"* ]]
  [[ "$output" == *"boot-recovery.sh notify"* ]]
  [[ "$output" == *"WantedBy=default.target"* ]]
}

@test "install: enables the notice user unit from the vendor dir" {
  local root="$FIXTURE/root" users="$FIXTURE/root/usr/lib/systemd/user"
  boot_recovery_install "$root" \
    "$BATS_TEST_DIRNAME/../../lib/boot/boot-recovery.sh"
  [ -f "$users/boot-recovery-notice.service" ]
  [ "$(readlink "$users/default.target.wants/boot-recovery-notice.service")" \
    = ../boot-recovery-notice.service ]
}

# _cut_before_depmod <version> — what an interruption before 60-depmod leaves:
# pacman removed the package files, only depmod's unowned modules.* remain.
_cut_before_depmod() {
  rm -rf "$FIXTURE/modules/$1"
  mkdir -p "$FIXTURE/modules/$1"
  echo stale >"$FIXTURE/modules/$1/modules.dep"
}

@test "should_restore: a tree left with only depmod's files still restores" {
  _kernel 6.18.40-1-lts linux-lts
  boot_recovery_stash "$FIXTURE/modules" linux-lts
  _cut_before_depmod 6.18.40-1-lts
  run boot_recovery_should_restore "$FIXTURE/modules" 6.18.40-1-lts
  [ "$status" -eq 0 ]
}

@test "restore: fills a surviving tree in place, never nesting the copy" {
  _kernel 6.18.40-1-lts linux-lts
  boot_recovery_stash "$FIXTURE/modules" linux-lts
  _cut_before_depmod 6.18.40-1-lts
  boot_recovery_restore "$FIXTURE/modules" 6.18.40-1-lts
  [ "$(cat "$FIXTURE/modules/6.18.40-1-lts/kernel/vfat.ko")" \
    = ko-6.18.40-1-lts ]
  [ ! -e "$FIXTURE/modules/6.18.40-1-lts/6.18.40-1-lts" ]
}

@test "restore: rebuilds the module dependencies for that release" {
  _kernel 6.18.40-1-lts linux-lts
  boot_recovery_stash "$FIXTURE/modules" linux-lts
  rm -rf "$FIXTURE/modules/6.18.40-1-lts"
  depmod() { echo "$*" >"$FIXTURE/depmod-called"; }
  boot_recovery_restore "$FIXTURE/modules" 6.18.40-1-lts
  [ "$(cat "$FIXTURE/depmod-called")" = 6.18.40-1-lts ]
}

@test "install: battery check first of all; the late legacy name goes" {
  local hooks="$FIXTURE/root/etc/pacman.d/hooks"
  mkdir -p "$hooks"
  : >"$hooks/92-battery-preflight.hook"
  boot_recovery_install "$FIXTURE/root" \
    "$BATS_TEST_DIRNAME/../../lib/boot/boot-recovery.sh"
  [ ! -e "$hooks/92-battery-preflight.hook" ]
  [ -f "$hooks/00-battery-preflight.hook" ]
  [[ "00-battery-preflight.hook" < "01-esp-kernel-sync-preflight.hook" ]]
}

# ── finishing an interrupted update ──────────────────────────────────────────

@test "finish_packages: restored kernels plus their installed headers" {
  mkdir -p "$FIXTURE/modules/.stash"
  printf '%s\n' "6.18.40-1-lts linux-lts" "7.0.1-1 linux" \
    >"$FIXTURE/modules/.stash/restored"
  boot_recovery_installed() { [[ "$1" != linux-headers ]]; }
  run boot_recovery_finish_packages "$FIXTURE/modules"
  [ "$output" = $'linux-lts\nlinux-lts-headers\nlinux' ]
}


@test "notice: names the one finish command" {
  mkdir -p "$FIXTURE/modules/.stash"
  echo "6.18.40-1-lts linux-lts" >"$FIXTURE/modules/.stash/restored"
  run boot_recovery_notice "$FIXTURE/modules"
  [[ "$output" == *"sudo /usr/local/lib/archzfs/boot-recovery.sh finish"* ]]
}

@test "unlock unit: clears a stale pacman lock before anything can run pacman" {
  run boot_recovery_unlock_unit
  [[ "$output" == *"After=local-fs.target"* ]]
  [[ "$output" == *"Before=sysinit.target"* ]]
  [[ "$output" == *"ConditionPathExists=/var/lib/pacman/db.lck"* ]]
  [[ "$output" == *"ExecStart=/usr/bin/rm -f /var/lib/pacman/db.lck"* ]]
}

@test "install: enables the unlock unit from the vendor dir" {
  boot_recovery_install "$FIXTURE/root" \
    "$BATS_TEST_DIRNAME/../../lib/boot/boot-recovery.sh"
  local units="$FIXTURE/root/usr/lib/systemd/system"
  [ -f "$units/boot-recovery-unlock.service" ]
  [ -L "$units/sysinit.target.wants/boot-recovery-unlock.service" ]
}

@test "finish_targets: the cached installed version, never a different one" {
  local cache="$FIXTURE/cache"
  mkdir -p "$cache"
  : >"$cache/linux-lts-6.18.59-1-x86_64.pkg.tar.zst"
  : >"$cache/linux-lts-6.18.59-1-x86_64.pkg.tar.zst.sig"
  : >"$cache/linux-lts-6.18.60-1-x86_64.pkg.tar.zst"
  # <name> <installed version> <repo version>
  run boot_recovery_finish_targets "$cache" <<'LINES'
linux-lts 6.18.59-1 6.18.60-1
linux-lts-headers 6.18.59-1 6.18.59-1
zfs-dkms 2.4.4-1 2.4.5-1
LINES
  [ "$output" = "$(printf '%s\n' \
    "$cache/linux-lts-6.18.59-1-x86_64.pkg.tar.zst" \
    sync:linux-lts-headers missing:zfs-dkms-2.4.4-1)" ]
}

@test "notice: the command comes first (popups cut the body at ~3 lines)" {
  mkdir -p "$FIXTURE/modules/.stash"
  echo "6.18.40-1-lts linux-lts" >"$FIXTURE/modules/.stash/restored"
  run boot_recovery_notice "$FIXTURE/modules"
  [[ "$output" == "Finish the interrupted kernel update with: sudo"\
" /usr/local/lib/archzfs/boot-recovery.sh finish"* ]]
}
