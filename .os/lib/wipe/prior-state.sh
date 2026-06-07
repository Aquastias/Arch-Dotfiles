#!/usr/bin/env bash
# =============================================================================
# lib/wipe/prior-state.sh — the Prior-State Decision (pure)
# =============================================================================
# Decides, from probed disk facts alone, which disks carry prior state and so
# need a make-blank wipe. The probing (wipefs / lsblk / dd sampling) is the
# orchestrator's I/O; this module only decides. No block-device access here, so
# the decision is unit-testable without a real disk.
#
# Sourced by 02-wipe.sh. main()-free, so sourcing is inert.
# =============================================================================

# wipe_disk_dirty SIG NPARTS NONZERO
#   SIG     — wipefs signature output ("" = none)
#   NPARTS  — child partition count (integer)
#   NONZERO — "1" if any sampled window held non-zero data
# Exit 0 (dirty → needs wipe) if any prior state is present, 1 (already blank).
wipe_disk_dirty() {
  local sig="$1" nparts="${2:-0}" nonzero="${3:-0}"
  [[ -n "$sig" ]] && return 0
  (( nparts > 0 )) && return 0
  [[ "$nonzero" == "1" ]] && return 0
  return 1
}

# wipe_select_to_wipe — the set to wipe, decided from probed facts (pure).
# Reads facts on stdin, one disk per line, pipe-separated:
#   <disk>|<is_live>|<sig>|<nparts>|<nonzero>
# A '|' delimiter (non-whitespace) is used so an empty <sig> field is preserved
# rather than collapsed the way a tab/space would be. Emits the disks that need
# wiping — dirty AND not the live medium — in input order. No block-device I/O:
# the caller probes, this decides.
wipe_select_to_wipe() {
  local disk is_live sig nparts nonzero
  while IFS='|' read -r disk is_live sig nparts nonzero; do
    [[ -z "$disk" ]] && continue
    [[ "$is_live" == "1" ]] && continue          # never the live medium
    wipe_disk_dirty "$sig" "$nparts" "$nonzero" && printf '%s\n' "$disk"
  done
  return 0
}
