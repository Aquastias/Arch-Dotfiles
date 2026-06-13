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

# ── critical vs optional classification (by *fallback* filename) ──────────

@test "critical files = entry-referenced non-fallback files" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  _entry arch-zfs-fallback vmlinuz-linux-lts intel-ucode.img \
    initramfs-linux-lts-fallback.img
  : >"$BOOT/vmlinuz-linux-lts"
  : >"$BOOT/intel-ucode.img"
  : >"$BOOT/initramfs-linux-lts.img"
  : >"$BOOT/initramfs-linux-lts-fallback.img"

  run esp_sync_critical_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  in_output intel-ucode.img
  in_output initramfs-linux-lts.img
  ! in_output initramfs-linux-lts-fallback.img
}

@test "optional files = entry-referenced fallback files only" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  _entry arch-zfs-fallback vmlinuz-linux-lts intel-ucode.img \
    initramfs-linux-lts-fallback.img
  : >"$BOOT/vmlinuz-linux-lts"
  : >"$BOOT/intel-ucode.img"
  : >"$BOOT/initramfs-linux-lts.img"
  : >"$BOOT/initramfs-linux-lts-fallback.img"

  run esp_sync_optional_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output initramfs-linux-lts-fallback.img
  ! in_output vmlinuz-linux-lts
  ! in_output initramfs-linux-lts.img
}

# ── install_critical: temp+rename + cmp; preserve old image on failure ────

@test "install_critical success: dst byte-equals src, returns 0, no .new" {
  printf 'NEWIMG' >"$BOOT/src.img"
  printf 'OLDIMG' >"$ESP/dst.img"
  run esp_sync_install_critical "$BOOT/src.img" "$ESP/dst.img"
  [ "$status" -eq 0 ]
  [ "$(cat "$ESP/dst.img")" = "NEWIMG" ]
  cmp -s "$BOOT/src.img" "$ESP/dst.img"
  [ ! -e "$ESP/dst.img.new" ]
}

@test "install_critical failure preserves old dst, non-zero, no .new" {
  printf 'OLDIMG' >"$ESP/dst.img"
  run esp_sync_install_critical "$BOOT/missing.img" "$ESP/dst.img"
  [ "$status" -ne 0 ]
  [ "$(cat "$ESP/dst.img")" = "OLDIMG" ] # prior good image intact
  [ ! -e "$ESP/dst.img.new" ]
}

# ── orphan_temps: list .new temps for the sweep ───────────────────────────

@test "orphan_temps lists .new temp files, not real files" {
  : >"$ESP/.vmlinuz-linux-lts.new"
  : >"$ESP/.initramfs-linux-lts.img.new"
  : >"$ESP/vmlinuz-linux-lts"
  run esp_sync_orphan_temps "$ESP"
  [ "$status" -eq 0 ]
  in_output "$ESP/.vmlinuz-linux-lts.new"
  in_output "$ESP/.initramfs-linux-lts.img.new"
  ! in_output "$ESP/vmlinuz-linux-lts"
}
