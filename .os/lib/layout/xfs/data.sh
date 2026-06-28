#!/usr/bin/env bash
# =============================================================================
# lib/layout/xfs/data.sh — xfs Data Group Formatter (ADR 0043)
# =============================================================================
# The per-filesystem leaf the layout dispatch (data_formatter_source xfs)
# sources. xfs is single-disk only (the validation contract rejects
# disk_count > 1). Shared work lives in the non-ZFS Data Group Formatter core;
# this file provides `_data_mkfs`.
# =============================================================================

# shellcheck source=../nonzfs/data.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/data.sh"

# Format the single data device xfs. -f: overwrite an existing signature.
_data_mkfs() { mkfs.xfs -f "$1"; }
