#!/usr/bin/env bash
# =============================================================================
# lib/wipe/probe.sh — already-blank detection (block-device I/O)
# =============================================================================
# Probes each target for prior state and drops the blank ones, so a zeroed
# disk is never zero-filled again. The decision itself is pure and lives in
# lib/wipe/prior-state.sh; this module only gathers the facts.
#
# Used by: 02-wipe.sh. Requires lib/common.sh, lib/live-medium.sh and
# lib/wipe/prior-state.sh. main()-free, so sourcing is inert.
# =============================================================================

# wipe_probe_disk DISK — one prior-state fact line for the pure decider:
#   <disk>|<is_live>|<sig>|<nparts>|<nonzero>
# sig/nparts (wipefs, lsblk) catch all structured data; nonzero samples 4 MiB at
# 33 offsets — heuristic, not an every-sector scan (a full multi-TB read would
# cost as much as the zero-fill it skips). Blank-by-decider is safe to install
# onto, so skipping is sound even if data hides between windows.
wipe_probe_disk() {
  local disk="$1" is_live=0 signature="" partition_count=0 nonzero=0

  live_medium_contains_disk "$disk" && is_live=1

  # Only probe a real block device. A resolved target set may name a disk absent
  # here (another host's disks); report it blank rather than run lsblk/dd,
  # which would fail under pipefail and trip the ERR trap. Can't wipe it anyway.
  if [[ -b "$disk" ]]; then
    # Presence only — wipefs output is multi-line, so collapse it to a token.
    [[ -n "$(wipefs "$disk" 2>/dev/null)" ]] && signature=present
    partition_count="$(lsblk -ln -o NAME "$disk" 2>/dev/null \
      | awk 'NR > 1 { count++ } END { print count + 0 }')"
    _probe_has_nonzero_data "$disk" && nonzero=1
  fi

  printf '%s|%s|%s|%s|%s\n' "$disk" "$is_live" "$signature" \
    "$partition_count" "$nonzero"
}

# _probe_has_nonzero_data DISK — 0 if any sampled window holds a non-zero
# byte: a 4 MiB window at 33 offsets (~132 MiB worst case).
_probe_has_nonzero_data() {
  local disk="$1" size
  size="$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)"
  ((size > 0)) || return 1
  local chunk=$((4 * 1024 * 1024))
  local windows=32
  local step=$((size > chunk ? (size - chunk) / windows : 0))
  local i offset nonzero_bytes
  for ((i = 0; i <= windows; i++)); do
    offset=$((i * step))
    ((offset > size - chunk)) && offset=$((size > chunk ? size - chunk : 0))
    nonzero_bytes="$(dd if="$disk" bs="$chunk" count=1 skip="$offset" \
      iflag=skip_bytes status=none 2>/dev/null \
      | LC_ALL=C awk 'BEGIN { RS = "\0" } { count += length($0) }
                      END { print count + 0 }')"
    ((nonzero_bytes > 0)) && return 0
  done
  return 1
}

# wipe_skip_blank_disks — drop already-blank disks from DISKS_TO_WIPE
# (reporting each skip): probe each target, then let the pure decider pick the
# set to wipe.
wipe_skip_blank_disks() {
  section "Checking for Already-Zeroed Disks"
  local disk kept=()
  mapfile -t kept < <(
    for disk in "${DISKS_TO_WIPE[@]}"; do wipe_probe_disk "$disk"; done \
      | wipe_select_to_wipe
  )
  # Report each disk the decider dropped as blank. (Live-medium disks are
  # aborted by the hard guard earlier, so a drop here is blank.)
  local -A kept_set=()
  for disk in "${kept[@]}"; do kept_set[$disk]=1; done
  for disk in "${DISKS_TO_WIPE[@]}"; do
    [[ -n "${kept_set[$disk]:-}" ]] \
      || info "Skipping $disk — already blank/zeroed (no wipe needed)."
  done
  DISKS_TO_WIPE=("${kept[@]}")
}
