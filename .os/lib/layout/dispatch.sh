#!/usr/bin/env bash
# =============================================================================
# lib/layout/dispatch.sh — filesystem-keyed layout dispatch (ADR 0040, 0043)
# =============================================================================
# Resolves which layout module to source for the active filesystem. ADR 0043
# splits the seam in two:
#   - root_adapter_source <os-dir> <fs> <mode>  → the Root Layout Adapter that
#     owns the OS disk (partition / format / boot). Keyed by filesystem × mode.
#   - data_formatter_source <os-dir> <fs>       → the Data Group Formatter that
#     formats one data group with its filesystem. Keyed by filesystem only.
#
# The ZFS adapter was relocated from the flat lib/layout/<mode>.sh into
# lib/layout/zfs/ when filesystem #2 landed (ADR 0043). Root adapters: zfs +
# ext4 + xfs + btrfs(single) are built. Data formatters: zfs/ext4/xfs/btrfs are
# built; an unbuilt filesystem errors here.
#
# Pure: string transforms on <os-dir>/<filesystem>/<mode>, no disk access.
# Uses error() from common.sh, available at call time.
# =============================================================================

# Root Layout Adapter for <fs> × <mode>. The OS-disk owner.
root_adapter_source() {
  local dir="$1" fs="$2" mode="$3"
  case "$fs" in
  zfs) printf '%s\n' "${dir}/lib/layout/zfs/${mode}.sh" ;;
  # ext4 is single-disk only (the validation contract rejects disk_count > 1),
  # so its one adapter owns the OS disk regardless of mode.
  ext4) printf '%s\n' "${dir}/lib/layout/ext4/single.sh" ;;
  # xfs is the same single-disk shape as ext4 (validation rejects disk_count > 1),
  # so its one adapter owns the OS disk regardless of mode.
  xfs) printf '%s\n' "${dir}/lib/layout/xfs/single.sh" ;;
  # btrfs carries native multi-disk topology, so (like zfs) the mode keys the
  # adapter file: single.sh owns one disk; multi.sh (raid) lands in a later pass.
  btrfs) printf '%s\n' "${dir}/lib/layout/btrfs/${mode}.sh" ;;
  *) error "No root layout adapter for filesystem '${fs}'" \
       "(ADR 0043 reserves it; zfs + ext4 + xfs + btrfs are implemented)." ;;
  esac
}

# Data Group Formatter for <fs>. Formats one data group; mode-independent. For
# ZFS the Standalone Data Pool creation (create_data_pools) lives in the multi
# module.
data_formatter_source() {
  local dir="$1" fs="$2"
  case "$fs" in
  zfs) printf '%s\n' "${dir}/lib/layout/zfs/multi.sh" ;;
  ext4) printf '%s\n' "${dir}/lib/layout/ext4/data.sh" ;;
  xfs) printf '%s\n' "${dir}/lib/layout/xfs/data.sh" ;;
  btrfs) printf '%s\n' "${dir}/lib/layout/btrfs/data.sh" ;;
  *) error "No data group formatter for filesystem '${fs}'" \
       "(zfs/ext4/xfs/btrfs are implemented)." ;;
  esac
}
