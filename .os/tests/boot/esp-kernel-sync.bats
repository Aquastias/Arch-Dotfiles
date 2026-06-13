#!/usr/bin/env bats
# Tests for lib/boot/esp-kernel-sync.sh — the ESP Kernel Sync planner.
#
# Sourced lib-only (ESP_KERNEL_SYNC_LIB_ONLY=1) so the runtime cp loop is
# skipped and only the pure planner is exercised (mirrors initcpio.sh's
# INITCPIO_LIB_ONLY guard). The planner drives the sync from the loader
# entries, so a Stray Kernel — which has no entry — is never mirrored.

setup() {
  ESP_KERNEL_SYNC_LIB_ONLY=1
  # shellcheck source=../../lib/boot/esp-kernel-sync.sh
  source "$BATS_TEST_DIRNAME/../../lib/boot/esp-kernel-sync.sh"

  ESP="$(mktemp -d)"
  BOOT="$(mktemp -d)"
  mkdir -p "$ESP/loader/entries"
}

teardown() { rm -rf "$ESP" "$BOOT"; }

# Write a loader entry: _entry <name> <vmlinuz> <initrd>...
_entry() {
  local f="$ESP/loader/entries/$1.conf" kernel="$2"
  shift 2
  {
    echo "title   test"
    echo "linux   /$kernel"
    local i
    for i in "$@"; do echo "initrd  /$i"; done
    echo "options root=ZFS=rpool/ROOT/arch rw"
  } >"$f"
}

in_output() { grep -qxF "$1" <<<"$output"; }

@test "planner emits entry-referenced files and excludes a stray kernel" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  : >"$BOOT/vmlinuz-linux-lts"
  : >"$BOOT/intel-ucode.img"
  : >"$BOOT/initramfs-linux-lts.img"
  # a stray rolling kernel present in /boot but named by NO entry
  : >"$BOOT/vmlinuz-linux"
  : >"$BOOT/initramfs-linux.img"

  run esp_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  in_output intel-ucode.img
  in_output initramfs-linux-lts.img
  ! in_output vmlinuz-linux
  ! in_output initramfs-linux.img
}

@test "planner omits an entry-referenced file missing from /boot" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  : >"$BOOT/vmlinuz-linux-lts" # only this one exists in /boot
  run esp_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  ! in_output intel-ucode.img
  ! in_output initramfs-linux-lts.img
}

@test "planner de-duplicates a file referenced by multiple entries" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  _entry arch-zfs-fallback vmlinuz-linux-lts intel-ucode.img \
    initramfs-linux-lts-fallback.img
  : >"$BOOT/vmlinuz-linux-lts"
  : >"$BOOT/intel-ucode.img"
  : >"$BOOT/initramfs-linux-lts.img"
  : >"$BOOT/initramfs-linux-lts-fallback.img"

  run esp_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  # vmlinuz-linux-lts is referenced by both entries — appears exactly once
  [ "$(grep -cxF vmlinuz-linux-lts <<<"$output")" -eq 1 ]
  in_output initramfs-linux-lts-fallback.img
}
