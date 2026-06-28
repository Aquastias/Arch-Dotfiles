#!/usr/bin/env bash
# =============================================================================
# lib/layout/btrfs/data.sh — btrfs Data Group Formatter (ADR 0043)
# =============================================================================
# The per-filesystem leaf the layout dispatch (data_formatter_source btrfs)
# sources. btrfs carries native multi-disk topology (raid0/1/10), so its mkfs
# may span several partitions; an absent/`single` topology is a single device.
# Shared work lives in the non-ZFS Data Group Formatter core; this file provides
# `_data_mkfs`, reading the core's `_DATA_TOPOLOGY` for the profile.
# =============================================================================

# shellcheck source=../nonzfs/data.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/data.sh"

# Format the data device(s) btrfs. With a real topology over multiple devices,
# apply it to both data and metadata; otherwise a plain single-device mkfs.
_data_mkfs() {
  local topo="${_DATA_TOPOLOGY:-single}"
  if [[ "$topo" == "single" || $# -eq 1 ]]; then
    mkfs.btrfs -f "$@"
  else
    mkfs.btrfs -f -d "$topo" -m "$topo" "$@"
  fi
}
