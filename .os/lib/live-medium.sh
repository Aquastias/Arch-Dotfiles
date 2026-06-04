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
_lm_boot_part() {
  local src
  src="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
  [[ -n "$src" ]] && { echo "$src"; return; }
  src="$(findmnt -no SOURCE / 2>/dev/null || true)"
  [[ -n "$src" && "$src" != "overlay" && "$src" != "airootfs" ]] \
    && echo "$src"
}

# Whole disk that owns DEV, via the kernel parent (PKNAME). When DEV is already
# a whole disk (no parent) it is returned unchanged.
_lm_parent_disk() {
  local dev="$1" pk
  [[ -n "$dev" ]] || return 0
  pk="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1 || true)"
  if [[ -n "$pk" ]]; then
    echo "/dev/${pk}"
  else
    echo "$dev"
  fi
}

# Devices carrying an iso9660 filesystem.
_lm_iso9660_parts() {
  blkid -t TYPE=iso9660 -o device 2>/dev/null || true
}

# Devices carrying an ARCH_* archiso label. blkid -t LABEL can't glob, so scan
# the export form: DEVNAME precedes LABEL within each device's block.
_lm_arch_label_parts() {
  blkid -o export 2>/dev/null \
    | awk -F= '/^DEVNAME=/{d=$2} /^LABEL=ARCH_/{print d}' || true
}

# ── Composer (pure decision over the seams) ──────────────────────────────────

# The set of whole disks that are the live medium, deduplicated, one per line.
live_medium_disks() {
  local parts=() disks=() p d boot
  boot="$(_lm_boot_part)"
  [[ -n "$boot" ]] && parts+=("$boot")
  while IFS= read -r p; do [[ -n "$p" ]] && parts+=("$p"); done \
    < <(_lm_iso9660_parts)
  while IFS= read -r p; do [[ -n "$p" ]] && parts+=("$p"); done \
    < <(_lm_arch_label_parts)

  for p in "${parts[@]}"; do
    d="$(_lm_parent_disk "$p")"
    [[ -n "$d" ]] && disks+=("$d")
  done
  ((${#disks[@]})) && printf '%s\n' "${disks[@]}" | sort -u || true
}

# 0 if DISK is part of the live medium, 1 otherwise. Used by the wipe to both
# exclude the medium from the disk list and hard-guard the wipe itself.
is_live_medium() {
  local target="$1" d
  while IFS= read -r d; do
    [[ "$d" == "$target" ]] && return 0
  done < <(live_medium_disks)
  return 1
}
