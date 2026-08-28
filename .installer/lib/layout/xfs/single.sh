#!/usr/bin/env bash
# =============================================================================
# lib/layout/xfs/single.sh — xfs Root Layout Adapter (single-disk, ADR 0043)
# =============================================================================
# A thin leaf over the shared non-ZFS root spine (lib/layout/nonzfs/root.sh),
# which owns partitioning, optional LUKS, formatting, mounting, and the
# filesystem-blind boot record. xfs is the same single-disk shape as ext4 (the
# validation contract rejects disk_count > 1), differing only in the mkfs
# command and the fstab fs-type column — the two hooks this leaf supplies.
# =============================================================================

# shellcheck source=../nonzfs/root.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/root.sh"

# Format the root device xfs. -f: overwrite an existing signature (the spine
# already wiped + repartitioned).
_root_mkfs() { mkfs.xfs -f "$1"; }

# The fstab fs-type column + log label for an xfs root.
_root_fstype() { echo xfs; }
