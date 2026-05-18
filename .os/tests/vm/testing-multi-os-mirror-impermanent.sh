#!/usr/bin/env bash
# =============================================================================
# vm/testing-multi-os-mirror-impermanent.sh — VM test: multi-mirror + imperm.
# =============================================================================
# Layout: 2 × 40 GiB SATA disks
#   /dev/sda + /dev/sdb → rpool (mirror)
#   no separate storage pool
# Config: mode=multi, os_pool.topology=mirror,
#         options.impermanence.enabled=true.
#
# Impermanence dataset creation is layout-agnostic: it runs in the chroot
# phase (lib/chroot/impermanence.sh) after the pool is already created by
# the layout module. No layout-specific wiring is needed.
#
# Post-install manual verification (harness installs only):
#   - all 5 Rollback Datasets exist on the mirrored rpool with @blank
#   - /persist is mounted from rpool/persist
#   - SSH host key survives reboot
#   - unpersisted /etc edit vanishes after reboot
#   - ESP mirror hook still installed and functions across pacman txns
#   - pacman resnapshot hook installed; test pkg install survives reboot
# =============================================================================

VM_NAME="arch-zfs-test-multi-mirror-impermanent"
VM_DISK_SIZES=(40 40)

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "vm-test-multi-mirror-imp",
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
    "esp_size":    "512M",
    "impermanence": {
      "enabled": true,
      "dataset": "rpool/persist",
      "mount":   "/persist"
    }
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
  "storage_groups": []
}'

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
