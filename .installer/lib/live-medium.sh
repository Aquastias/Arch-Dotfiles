#!/usr/bin/env bash
# =============================================================================
# lib/live-medium.sh — the Live-Medium Detector
# =============================================================================
# Identifies the installer's own medium so the Disk Wipe never lists, selects,
# or erases it. Pure module with injectable seams (the `_lm_*` wrappers), each
# of which wraps exactly one system query so it can be overridden in tests.
#
# The detector unions several signals, then resolves every hit to its whole
# disk via the *kernel parent* (lsblk PKNAME) — never by stripping trailing
# digits, which mangles by-label/by-uuid source paths.
#
# Sourced by 02-wipe.sh. main()-free, so sourcing is inert.
# =============================================================================

# ── Injectable seams (one system query each) ─────────────────────────────────

# The partition the live ISO booted from, or empty (e.g. a copytoram boot where
# the USB is unmounted). archiso bootmnt first, then the live root.
_live_medium_boot_partition() {
  local device
  device="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
  [[ -n "$device" ]] && { echo "$device"; return; }
  device="$(findmnt -no SOURCE / 2>/dev/null || true)"
  [[ -n "$device" && "$device" != "overlay" && "$device" != "airootfs" ]] \
    && echo "$device"
  # Found-nothing is normal (copytoram / airootfs boot). Return success so the
  # caller's `boot="$(_live_medium_boot_partition)"` under `set -Eeuo pipefail`
  # doesn't inherit the trailing test's non-zero status and trip the ERR trap.
  return 0
}

# Whole disk that owns DEV, via the kernel parent (PKNAME). When DEV is already
# a whole disk (no parent) it is returned unchanged.
_live_medium_parent_disk() {
  local dev="$1" parent
  [[ -n "$dev" ]] || return 0
  parent="$(lsblk -no PKNAME "$dev" 2>/dev/null | awk 'NR == 1' || true)"
  if [[ -n "$parent" ]]; then
    echo "/dev/${parent}"
  else
    echo "$dev"
  fi
}

# Devices carrying an iso9660 filesystem.
_live_medium_iso9660_partitions() {
  blkid -t TYPE=iso9660 -o device 2>/dev/null || true
}

# Devices carrying an ARCH_* archiso label. blkid -t LABEL can't glob, so scan
# the export form: DEVNAME precedes LABEL within each device's block.
_live_medium_arch_label_partitions() {
  blkid -o export 2>/dev/null \
    | awk -F= '/^DEVNAME=/{d=$2} /^LABEL=ARCH_/{print d}' || true
}

# ── Composer (pure decision over the seams) ──────────────────────────────────

# The set of whole disks that are the live medium, deduplicated, one per line.
live_medium_disks() {
  local partitions=() disks=() partition disk boot
  boot="$(_live_medium_boot_partition)"
  [[ -n "$boot" ]] && partitions+=("$boot")
  while IFS= read -r partition; do
    [[ -n "$partition" ]] && partitions+=("$partition")
  done < <(_live_medium_iso9660_partitions; _live_medium_arch_label_partitions)

  for partition in "${partitions[@]}"; do
    disk="$(_live_medium_parent_disk "$partition")"
    [[ -n "$disk" ]] && disks+=("$disk")
  done
  ((${#disks[@]})) && printf '%s\n' "${disks[@]}" | sort -u || true
}

# 0 if DISK is part of the live medium, 1 otherwise. Used by the wipe to both
# exclude the medium from the disk list and hard-guard the wipe itself.
live_medium_contains_disk() {
  local target="$1" disk
  while IFS= read -r disk; do
    [[ "$disk" == "$target" ]] && return 0
  done < <(live_medium_disks)
  return 1
}
