#!/usr/bin/env bats
# Tests for .os/lib/live-medium.sh — the Live-Medium Detector.
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
  _lm_boot_part()        { echo /dev/sdb1; }
  _lm_iso9660_parts()    { :; }
  _lm_arch_label_parts() { :; }
  # Real _lm_parent_disk runs; PKNAME resolves the kernel parent.
  lsblk() { [[ "$*" == *"PKNAME"* ]] && echo sdb; }
  run live_medium_disks
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sdb" ]
}

# ── Signal: iso9660 (works unmounted — copytoram) ───────────────────────────

@test "iso9660: a disk carrying an iso9660 partition is the live medium" {
  _lm_boot_part()        { :; }            # nothing mounted (copytoram)
  _lm_arch_label_parts() { :; }
  blkid() { [[ "$*" == *"TYPE=iso9660"* ]] && echo /dev/sdb1; }
  lsblk() { [[ "$*" == *"PKNAME /dev/sdb1"* ]] && echo sdb; }
  run live_medium_disks
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sdb" ]
}

# ── Robustness: by-label boot source ────────────────────────────────────────

@test "by-label boot source resolves via the kernel parent, not digit-strip" {
  _lm_boot_part()        { echo /dev/disk/by-label/ARCH_202401; }
  _lm_iso9660_parts()    { :; }
  _lm_arch_label_parts() { :; }
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
  _lm_boot_part()     { :; }
  _lm_iso9660_parts() { :; }
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
  _lm_boot_part() { :; }                        # USB unmounted
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

# ── Predicate: is_live_medium ───────────────────────────────────────────────

@test "is_live_medium: true for the live disk, false for a data disk" {
  _lm_boot_part()        { echo /dev/sdb1; }
  _lm_iso9660_parts()    { :; }
  _lm_arch_label_parts() { :; }
  lsblk() { [[ "$*" == *"PKNAME /dev/sdb1"* ]] && echo sdb; }
  run is_live_medium /dev/sdb
  [ "$status" -eq 0 ]
  run is_live_medium /dev/sda
  [ "$status" -ne 0 ]
}
