#!/usr/bin/env bash
# =============================================================================
# vm/testing-multi-os-mirror-storage.sh — VM test: OS mirror + storage mirror
# =============================================================================
# Layout: 4 × SATA disks
#   /dev/sda (40 GiB) + /dev/sdb (40 GiB) → rpool (mirror)
#   /dev/sdc (20 GiB) + /dev/sdd (20 GiB) → dpool/DATA/data (mirror)
# =============================================================================

VM_NAME="arch-zfs-test-multi-mirror-storage"
VM_DISK_SIZES=(40 40 20 20)

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "vm-test-multi-mirror-storage",
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
    "topology":  "mirror",
    "ashift":    12,
    "disks":     ["/dev/sda", "/dev/sdb"]
  },
  "storage_groups": [
    {
      "name":     "data",
      "mount":    "/data",
      "ashift":   12,
      "topology": "mirror",
      "disks":    ["/dev/sdc", "/dev/sdd"]
    }
  ]
}'

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
