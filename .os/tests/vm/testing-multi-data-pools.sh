#!/usr/bin/env bash
# =============================================================================
# vm/testing-multi-data-pools.sh — VM test: Standalone Data Pools end-to-end
# =============================================================================
# Layout: 4 × 20 GiB SATA disks (ADR 0027, issue 06)
#   /dev/sda → rpool         (OS, topology=none, single disk)
#   /dev/sdb → tank0         (Standalone Data Pool, single-disk stripe)
#   /dev/sdc + /dev/sdd → tank1  (Standalone Data Pool, 2-disk mirror)
#
# Exercises the real zpool/sgdisk paths unit tests can't: declarative
# data_pools[] are partitioned, created, and exported by the installer, then
# auto-imported on first boot. VERIFY_BOOT injects a first-boot unit that runs
# the unit-tested verifier (lib/vm-pool-verify.sh) and emits the boot sentinel
# only when every pool imported and every <name>/data dataset is mounted at its
# mountpoint — so the test fails loudly (host timeout) on any missing/unmounted
# pool.
# =============================================================================

VM_NAME="arch-zfs-test-multi-data-pools"
VM_DISK_SIZES=(20 20 20 20)

# Verify the installed system on first boot (the point of this smoke test).
VERIFY_BOOT=true

# Booted-system expectations consumed by the verify-boot first-boot unit.
VM_VERIFY_POOLS=(rpool tank0 tank1)
VM_VERIFY_MOUNTS=(tank0/data:/data/tank0 tank1/data:/data/tank1)

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "vm-test-multi-data-pools",
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
