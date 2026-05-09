#!/usr/bin/env bash
# =============================================================================
# vm/testing-multi-os-none.sh — VM test: multi-disk, no OS RAID
# =============================================================================
# Layout: 2 × 40 GiB SATA disks
#   topology=none + 2 disks listed → unattended auto-picks /dev/sda for OS
#   /dev/sda → rpool (single disk)
#   /dev/sdb → dpool (leftover, independent vdev)
#
# pick_option auto-selects option 1 when INSTALL_UNATTENDED=1, so /dev/sda
# is always chosen as the OS disk and /dev/sdb folds into the storage pool.
# =============================================================================

VM_NAME="arch-zfs-test-multi-none"
VM_DISK_SIZES=(40 40)

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "vm-test-multi-none",
    "locale":   "en_US.UTF-8",
    "timezone": "UTC",
    "keymap":   "us"
  },
  "options": {
    "kernel":      "lts",
    "bootloader":  "systemd-boot",
    "encryption":  false,
    "swap":        true,
    "swap_size":   "auto",
    "esp_size":    "512M"
  },
  "packages": { "extra": [], "groups": {} },
  "post_install": {
    "backup": false,
    "security": false,
    "desktop": { "kde": false }
  },
  "mode": "multi",
  "os_pool": {
    "pool_name": "rpool",
    "topology":  "none",
    "ashift":    12,
    "disks":     ["/dev/sda", "/dev/sdb"]
  },
  "storage_groups": []
}'

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
