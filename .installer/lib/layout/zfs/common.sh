#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/common.sh — ZFS Layout Module helpers
# =============================================================================
# Sourced by layout-single.sh and layout-multi.sh. The filesystem-agnostic
# spine (phase lifecycle, size parsers, ESP helpers, the layout_plan verb +
# seam hooks, partition contract) was extracted to lib/layout/core.sh (ADR
# 0043); this file keeps only the ZFS-specific plan contract and sources the
# ZFS leftover-disk adapter + boot-record publisher in plan.sh.
# Requires: lib/common.sh already sourced (provides cfgo, error, part_name).
# =============================================================================

# shellcheck source=../core.sh
source "${BASH_SOURCE[0]%/*}/../core.sh"

# ZFS plan contract: beyond the shared ESP check (core), the OS pool name must
# be resolved. Overrides core's ESP-only default. Call at end of layout_plan().
_layout_verify_plan_contract() {
  [[ -n "$LAYOUT_OS_POOL_NAME" ]] ||
    error "Layout contract: LAYOUT_OS_POOL_NAME must be non-empty" \
          "after layout_plan()"
  ((${#LAYOUT_ESP_PARTS[@]} >= 1)) ||
    error "Layout contract: LAYOUT_ESP_PARTS must have ≥1 element" \
          "after layout_plan()"
}

# Start a fresh GPT on one ZFS OS disk: wipe existing signatures + tables, then
# create partition 1 as the ESP (ef00, sized). The shared head of both the
# single-disk (partition_single_disk) and multi-disk (partition_os_disks_multi)
# rituals — the caller adds the bf00 pool member partition(s) and mkfs.fat's the
# ESP. `esp_sz` is a raw sgdisk size (e.g. "512M"/"2G") from layout_resolve_esp_size.
_zfs_partition_esp_start() {
  local disk="$1" esp_sz="$2"
  wipefs -af "$disk"
  sgdisk --zap-all "$disk"
  sgdisk -n1:0:+"${esp_sz}" -t1:ef00 -c1:"EFI System" "$disk"
}

# The ZFS leftover-disk adapter + the ZFS boot-record publisher (the
# _layout_publish_boot override) live in plan.sh. Sourced last so core's
# defaults are already defined and these override them.
# shellcheck source=./plan.sh
source "${BASH_SOURCE[0]%/*}/plan.sh"
