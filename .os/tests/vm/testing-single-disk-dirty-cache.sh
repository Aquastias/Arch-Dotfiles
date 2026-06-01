#!/usr/bin/env bash
# =============================================================================
# vm/testing-single-disk-dirty-cache.sh — VM test: dirty-ISO boot verify
# =============================================================================
# Layout: 1 × 40 GiB SATA disk (/dev/sda)
# Config: repo's install.jsonc as-is (mode=single), hostname patched at runtime.
#
# Regression guard for the ZFS root boot bug: a stale/corrupt zpool.cache on
# the live ISO must NOT brick the installed system. This fixture corrupts
# /etc/zfs/zpool.cache before install (DIRTY_CACHE), then power-cycles to the
# installed disk and confirms it reaches the first-boot sentinel (VERIFY_BOOT).
# Reverting the per-pool seeding fix or the zfs_import_dir boot guard makes it
# fail. Heavy (~doubles runtime) — run on demand, not in the fast path.
# =============================================================================

VM_NAME="arch-zfs-test-single-dirty"
VM_DISK_SIZES=(40)

# Boot-verify fixture: both knobs on (the harness also accepts --verify-boot).
DIRTY_CACHE=true
VERIFY_BOOT=true

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
