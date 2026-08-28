#!/usr/bin/env bash
# =============================================================================
# lib/layout/nonzfs/plan.sh — shared non-ZFS partition planner (ADR 0043)
# =============================================================================
# The pure arithmetic core under the ext4/xfs/btrfs Root Adapters. A non-ZFS
# root disk is laid out as `ESP + [swap] + root`, where root takes the
# remainder. This module computes that split and validates it; the adapter
# turns the emitted plan into sgdisk calls (the disk-touching part).
#
# Pure: integer math on its MiB arguments, no disk access. Uses error() from
# common.sh, available at call time.
#
# Public API:
#   nonzfs_partition_plan <total_mib> <esp_mib> <swap_mib>
#     → emits a `key=value` plan on stdout: sizes (esp_mib, swap_mib, root_mib)
#       and the partition slots (esp_part_num, swap_part_num, root_part_num).
#       swap_mib 0 means no swap partition: swap_part_num is empty and
#       root_part_num shifts down to 2. The plan is the single authority for
#       partition numbering — both the sgdisk partitioner and the device
#       resolver read these slots rather than re-deriving them. Errors when root
#       would be too small.
# =============================================================================

# Minimum usable root partition (MiB) — a floor below which the install is not
# viable. Lower than ZFS's because a bare ext4/xfs root has no pool overhead.
_NONZFS_ROOT_FLOOR_MIB=8192

# 1 MiB at the start + 1 MiB guard at the end (GPT header + alignment).
_NONZFS_ALIGN_MIB=2

nonzfs_partition_plan() {
  local total_mib="$1" esp_mib="$2" swap_mib="$3"

  ((esp_mib > 0)) || error "Partition plan: ESP size must be positive."
  ((swap_mib >= 0)) || error "Partition plan: swap size cannot be negative."

  local root_mib=$((total_mib - esp_mib - swap_mib - _NONZFS_ALIGN_MIB))
  if ((root_mib < _NONZFS_ROOT_FLOOR_MIB)); then
    error "Partition plan: root would be ${root_mib} MiB, below the" \
      "${_NONZFS_ROOT_FLOOR_MIB} MiB floor (disk ${total_mib} MiB," \
      "ESP ${esp_mib}, swap ${swap_mib}). Use a larger disk or less swap."
  fi

  # Assign slots from the same swap decision that drives the sizes: ESP is
  # always 1; a swap partition (when sized) is 2 and pushes root to 3; with no
  # swap, root takes 2. Emitting these makes the plan the one place that decides
  # partition numbering.
  local swap_part_num root_part_num
  if ((swap_mib > 0)); then
    swap_part_num=2
    root_part_num=3
  else
    swap_part_num=""
    root_part_num=2
  fi

  printf 'esp_mib=%s\n' "$esp_mib"
  printf 'swap_mib=%s\n' "$swap_mib"
  printf 'root_mib=%s\n' "$root_mib"
  printf 'esp_part_num=%s\n' 1
  printf 'swap_part_num=%s\n' "$swap_part_num"
  printf 'root_part_num=%s\n' "$root_part_num"
}
