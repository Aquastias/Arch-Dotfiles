#!/usr/bin/env bash
# =============================================================================
# vm/testing-single-disk.sh — VM test: single-disk install
# =============================================================================
# Layout: 1 × 40 GiB SATA disk (/dev/sda)
# Config: repo's install.jsonc as-is (mode=single, disk=/dev/sda), hostname
#         patched to TEST_HOSTNAME at runtime.
# =============================================================================

VM_NAME="arch-zfs-test-single"
VM_DISK_SIZES=(40)

# INSTALL_CONFIG_CONTENT is intentionally unset → single-disk seed path:
# the harness patches only the hostname in the repo's existing install.jsonc.

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
