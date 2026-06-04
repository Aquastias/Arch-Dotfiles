#!/usr/bin/env bash
# =============================================================================
# lib/wipe-method.sh — the Wipe-Method Selector
# =============================================================================
# Pure routing from a disk's rotational flag to a make-blank method:
#   non-rotational (SSD/NVMe) → blkdiscard   (instant, no flash wear)
#   rotational     (HDD)      → dd           (single zero-pass)
# shred/secure-erase is never selected — the purpose is make-blank.
#
# Sourced by 02-wipe.sh. main()-free, so sourcing is inert.
# =============================================================================

# wipe_method ROTA
#   ROTA — lsblk ROTA value: 0 non-rotational, 1 rotational.
# Echoes the method: "blkdiscard" or "dd".
wipe_method() {
  case "$1" in
    0) echo "blkdiscard" ;;
    *) echo "dd" ;;  # rotational, or unknown → safe full zero-pass
  esac
}
