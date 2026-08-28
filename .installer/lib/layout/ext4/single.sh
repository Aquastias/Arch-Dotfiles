#!/usr/bin/env bash
# =============================================================================
# lib/layout/ext4/single.sh — ext4 Root Layout Adapter (single-disk, ADR 0043)
# =============================================================================
# A thin leaf over the shared non-ZFS root spine (lib/layout/nonzfs/root.sh),
# which owns partitioning, optional LUKS, formatting, mounting, and the
# filesystem-blind boot record. ext4 is single-disk only (the validation
# contract rejects disk_count > 1). This leaf supplies only the two
# filesystem-specific hooks the spine calls.
# =============================================================================

# shellcheck source=../nonzfs/root.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/root.sh"

# Format the root device ext4. -F: don't prompt over an old signature (the spine
# already wiped + repartitioned).
_root_mkfs() { mkfs.ext4 -F "$1"; }

# The fstab fs-type column + log label for an ext4 root.
_root_fstype() { echo ext4; }
