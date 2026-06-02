#!/usr/bin/env bash
# =============================================================================
# vm/testing-multi-data-pools-reorder.sh — VM test: data pools survive a
# disk-enumeration reorder across reboot (ADR 0028)
# =============================================================================
# Same layout as testing-multi-data-pools.sh (rpool + tank0 + tank1 over 4
# disks of DIFFERENT sizes), but between install and first boot the harness
# permutes the data-disk backing files so the kernel assigns /dev/sdX in a
# different order than the installer saw. This is the faithful reproduction of
# the field bug: a data pool recorded by a bare /dev/sdX kernel name fails to
# import on the reordered boot ("one or more devices is currently
# unavailable"), while pools recorded by stable /dev/disk/by-id or by-partuuid
# paths (the fix) follow their disk and import cleanly.
#
# The boot-verify sentinel only fires when every pool imported, every data
# dataset is mounted, AND every leaf vdev resolves to a stable path
# (VM_VERIFY_BYID). On unfixed code this times out → the test fails loudly.
#
# Disks are intentionally varied in size to mirror the reporting hardware and
# nudge enumeration order to differ.
# =============================================================================

VM_NAME="arch-zfs-test-multi-data-pools-reorder"
VM_DISK_SIZES=(20 30 25 25)

VERIFY_BOOT=true
VM_REORDER_BOOT_DISKS=true

VM_VERIFY_POOLS=(rpool tank0 tank1)
VM_VERIFY_MOUNTS=(tank0/data:/data/tank0 tank1/data:/data/tank1)
VM_VERIFY_BYID=true

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "vm-test-multi-data-pools-reorder",
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
    "disks":     ["/dev/sda"]
  },
  "storage_groups": [],
  "data_pools": [
    { "name": "tank0", "topology": "stripe", "disks": ["/dev/sdb"] },
    { "name": "tank1", "topology": "mirror", "disks": ["/dev/sdc", "/dev/sdd"] }
  ]
}'

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
