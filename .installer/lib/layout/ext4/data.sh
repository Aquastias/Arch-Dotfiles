#!/usr/bin/env bash
# =============================================================================
# lib/layout/ext4/data.sh — ext4 Data Group Formatter (ADR 0043)
# =============================================================================
# The per-filesystem leaf the layout dispatch (data_formatter_source ext4)
# sources. ext4 is single-disk only (the validation contract rejects
# disk_count > 1), so its mkfs takes one device. All the shared work —
# partition, optional LUKS, mount, fstab/crypttab — lives in the non-ZFS Data
# Group Formatter core, which this file provides `_data_mkfs` to.
# =============================================================================

# shellcheck source=../nonzfs/data.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/data.sh"

# Format the single data device ext4. -F: don't prompt when it's a whole disk
# / has an old signature (the core already wiped + repartitioned).
_data_mkfs() { mkfs.ext4 -F "$1"; }
