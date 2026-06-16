#!/usr/bin/env bash
# =============================================================================
# lib/layout/dispatch.sh — filesystem-keyed layout adapter seam (ADR 0040)
# =============================================================================
# Resolves which Layout Module to source for the active filesystem + mode. The
# installer's layout dispatch was mode-keyed (lib/layout/<mode>.sh); ADR 0040
# generalizes it to a filesystem-keyed seam so btrfs/ext4/xfs adapters can land
# later without a schema migration. ZFS is the only implemented adapter and
# keeps the flat lib/layout/<mode>.sh path — relocating those files into a
# zfs/ subdir is the BASH_SOURCE foldering hazard, deferred to filesystem #2.
#
# Pure: a string transform on <os-dir>/<filesystem>/<mode>, no disk access.
# Uses error() from common.sh, available at call time.
#
# Public API:
#   layout_adapter_source <os-dir> <filesystem> <mode>
#     → the adapter file to source on stdout; errors for an unbuilt filesystem.
# =============================================================================

layout_adapter_source() {
  local dir="$1" fs="$2" mode="$3"
  case "$fs" in
  zfs) printf '%s\n' "${dir}/lib/layout/${mode}.sh" ;;
  *) error "No layout adapter for filesystem '${fs}'" \
       "(ADR 0040 reserves it; only zfs is implemented)." ;;
  esac
}
