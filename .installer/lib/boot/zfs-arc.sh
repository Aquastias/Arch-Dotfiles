#!/usr/bin/env bash
# =============================================================================
# lib/boot/zfs-arc.sh — ZFS ARC cap kernel command-line fragment (deep, pure)
# =============================================================================
# options.zfs.arc_max caps ZFS's ARC (default: up to half of RAM) so games on a
# 16 GB laptop keep their memory (ADR 0161). The Arch Wiki (ZFS, ARC) sets it
# as the `zfs.zfs_arc_max=<bytes>` kernel parameter, so the installer owns it
# like zswap.sh: every Bootloader Adapter appends this fragment. Also sourced
# host-side by validation, which reuses zfs_arc_max_bytes.
#
# Public API:
#   zfs_arc_max_bytes <size>             → bytes; non-zero on a bad size
#   zfs_arc_cmdline_params <state-json>  → the fragment, or empty when unset
# =============================================================================

# zfs_arc_max_bytes <size> — <digits>[K|M|G|T] (binary units) to bytes; 0 and
# anything else (4GB, -1G, 1.5G) is rejected.
zfs_arc_max_bytes() {
  local size="$1" number unit
  [[ "$size" =~ ^([0-9]+)([KMGT]?)$ ]] || return 1
  number="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[2]}"
  (( 10#$number > 0 )) || return 1
  case "$unit" in
    K) echo $(( 10#$number << 10 )) ;;
    M) echo $(( 10#$number << 20 )) ;;
    G) echo $(( 10#$number << 30 )) ;;
    T) echo $(( 10#$number << 40 )) ;;
    *) echo $(( 10#$number )) ;;
  esac
}

# zfs_arc_cmdline_params <state-json> — empty on a non-ZFS root or an unset
# cap. A bad size never reaches here: validation rejects it before install.
zfs_arc_cmdline_params() {
  local size bytes
  size="$(jq -r 'if .filesystem == "zfs" then .zfs.arc_max // "" else "" end' \
    <<<"$1")"
  [[ -n "$size" ]] || return 0
  bytes="$(zfs_arc_max_bytes "$size")" || return 0
  echo "zfs.zfs_arc_max=${bytes}"
}
