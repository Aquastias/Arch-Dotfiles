#!/usr/bin/env bash
# =============================================================================
# vm/testing-multi-os-stripe.sh — VM test: multi-disk OS stripe
# =============================================================================
# Layout: 2 × 40 GiB SATA disks
#   /dev/sda + /dev/sdb → rpool (stripe / RAID-0)
#   no separate storage pool
# =============================================================================

VM_NAME="arch-zfs-test-multi-stripe"
VM_DISK_SIZES=(40 40)

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "vm-test-multi-stripe",
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
    "topology":  "stripe",
    "ashift":    12,
    "disks":     ["/dev/sda", "/dev/sdb"]
  },
  "storage_groups": []
}'

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
