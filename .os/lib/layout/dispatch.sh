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
# lib/layout/zfs/ when filesystem #2 landed (ADR 0043). ZFS is the only built
# adapter; every other filesystem errors here.
#
# Pure: string transforms on <os-dir>/<filesystem>/<mode>, no disk access.
# Uses error() from common.sh, available at call time.
# =============================================================================

# Root Layout Adapter for <fs> × <mode>. The OS-disk owner.
root_adapter_source() {
  local dir="$1" fs="$2" mode="$3"
  case "$fs" in
  zfs) printf '%s\n' "${dir}/lib/layout/zfs/${mode}.sh" ;;
  *) error "No root layout adapter for filesystem '${fs}'" \
       "(ADR 0043 reserves it; only zfs is implemented)." ;;
  esac
}

# Data Group Formatter for <fs>. Formats one data group; mode-independent. For
# ZFS the Standalone Data Pool creation (create_data_pools) lives in the multi
# module.
data_formatter_source() {
  local dir="$1" fs="$2"
  case "$fs" in
  zfs) printf '%s\n' "${dir}/lib/layout/zfs/multi.sh" ;;
  *) error "No data group formatter for filesystem '${fs}'" \
       "(ADR 0043 reserves it; only zfs is implemented)." ;;
  esac
}
