#!/usr/bin/env bats
# Tests for .installer/lib/live-medium.sh — the Live-Medium Detector.
#
# Identifies the installer's own medium so the wipe never lists, selects, or
# erases it. Multiple signals: the parent disk of the boot mount (resolved via
# the kernel parent, not by stripping digits), plus any disk carrying an
# iso9660 partition or an ARCH_* archiso label. Pure module with injectable
# seams, so every signal is testable without a real USB.
#
# Strategy mirrors wipe-prior-state.bats: source the module and override the
# thin seams (or the underlying command) to simulate system state.

setup() {
  # shellcheck source=../lib/live-medium.sh
  source "$BATS_TEST_DIRNAME/../lib/live-medium.sh"
}

# ── Signal: boot-mount parent disk ──────────────────────────────────────────

@test "boot-mount: the boot partition's parent disk is the live medium" {
  _live_medium_boot_partition()        { echo /dev/sdb1; }
  _live_medium_iso9660_partitions()    { :; }
  _live_medium_arch_label_partitions() { :; }
  # Real _live_medium_parent_disk runs; PKNAME resolves the kernel parent.
  lsblk() { [[ "$*" == *"PKNAME"* ]] && echo sdb; }
  run live_medium_disks
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sdb" ]
}

# ── Signal: iso9660 (works unmounted — copytoram) ───────────────────────────

@test "iso9660: a disk carrying an iso9660 partition is the live medium" {
  _live_medium_boot_partition()        { :; }            # nothing mounted (copytoram)
  _live_medium_arch_label_partitions() { :; }
  blkid() { [[ "$*" == *"TYPE=iso9660"* ]] && echo /dev/sdb1; }
  lsblk() { [[ "$*" == *"PKNAME /dev/sdb1"* ]] && echo sdb; }
  run live_medium_disks
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sdb" ]
}

# ── Robustness: by-label boot source ────────────────────────────────────────

@test "by-label boot source resolves via the kernel parent, not digit-strip" {
  _live_medium_boot_partition()        { echo /dev/disk/by-label/ARCH_202401; }
  _live_medium_iso9660_partitions()    { :; }
  _live_medium_arch_label_partitions() { :; }
  # Stripping trailing digits would mangle the label path; PKNAME doesn't.
  lsblk() {
    [[ "$*" == *"PKNAME /dev/disk/by-label/ARCH_202401"* ]] && echo sdb
  }
  run live_medium_disks
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sdb" ]
}

# ── Signal: ARCH_* archiso label (works unmounted) ──────────────────────────

@test "ARCH_* label: a disk with an archiso label is the live medium" {
  _live_medium_boot_partition()     { :; }
  _live_medium_iso9660_partitions() { :; }
  blkid() {
    [[ "$*" == *"-o export"* ]] || return 0
    printf '%s\n' DEVNAME=/dev/sdb1 LABEL=ARCH_202401 TYPE=iso9660
  }
  lsblk() { [[ "$*" == *"PKNAME /dev/sdb1"* ]] && echo sdb; }
  run live_medium_disks
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sdb" ]
}

# ── copytoram: unmounted USB still caught by the non-mount signals ───────────

@test "copytoram: unmounted USB caught via iso9660 + ARCH_*, deduped" {
  _live_medium_boot_partition() { :; }                        # USB unmounted
  blkid() {
    case "$*" in
      *"TYPE=iso9660"*) echo /dev/sdb1 ;;
      *"-o export"*)    printf '%s\n' DEVNAME=/dev/sdb1 LABEL=ARCH_202401 ;;
    esac
  }
  lsblk() { [[ "$*" == *"PKNAME /dev/sdb1"* ]] && echo sdb; }
  run live_medium_disks
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sdb" ]                     # one line, not duplicated
}

# ── Regression: airootfs/copytoram boot must not trip the ERR trap ──────────
# The other tests stub _live_medium_boot_partition, so the real function's exit status was
# never exercised. On an airootfs/copytoram boot (bootmnt unmounted, / is
# "airootfs") its trailing `[[ ]] && echo` test is false; it must still exit 0
# so `boot="$(_live_medium_boot_partition)"` under `set -e` doesn't fire the wipe ERR trap
# ("Wipe script failed at line 59").
@test "airootfs boot: _live_medium_boot_partition exits 0 under set -e (no line-59 failure)" {
  run bash -c '
    set -Eeuo pipefail
    trap "exit 42" ERR
    source "'"$BATS_TEST_DIRNAME"'/../lib/live-medium.sh"
    findmnt() { case "${!#}" in
      /run/archiso/bootmnt) return 1 ;; /) echo airootfs ;; *) return 1 ;;
    esac; }
    export -f findmnt
    live_medium_disks
  '
  [ "$status" -eq 0 ]
}

# ── Predicate: live_medium_contains_disk ───────────────────────────────────────────────

@test "live_medium_contains_disk: true for the live disk, false for a data disk" {
  _live_medium_boot_partition()        { echo /dev/sdb1; }
  _live_medium_iso9660_partitions()    { :; }
  _live_medium_arch_label_partitions() { :; }
  lsblk() { [[ "$*" == *"PKNAME /dev/sdb1"* ]] && echo sdb; }
  run live_medium_contains_disk /dev/sdb
  [ "$status" -eq 0 ]
  run live_medium_contains_disk /dev/sda
  [ "$status" -ne 0 ]
}
