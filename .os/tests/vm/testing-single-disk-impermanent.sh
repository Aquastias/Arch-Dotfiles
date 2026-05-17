#!/usr/bin/env bash
# =============================================================================
# vm/testing-single-disk-impermanent.sh — VM test: impermanence enabled
# =============================================================================
# Layout: 1 × 40 GiB SATA disk (/dev/sda)
# Config: mode=single, options.impermanence.enabled=true.
#
# After install, verify in the booted VM:
#   - all 5 Rollback Datasets exist with @blank snapshots
#   - /persist is mounted
#   - the curated persist .mount units are active
#   - SSH host key survives reboot
#   - an unpersisted /etc/touch-me write disappears after reboot
# (The post-install reboot probe is currently a manual step — the harness
#  only runs the installer.)
# =============================================================================

VM_NAME="arch-zfs-test-single-impermanent"
VM_DISK_SIZES=(40)

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "vm-test-imp",
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
    "backup":   false,
    "security": false
  },
  "mode":              "single",
  "disk":              "/dev/sda",
  "ashift":            12,
  "os_size":           "32G",
  "os_pool_name":      "rpool",
  "storage_pool_name": "dpool",
  "storage_mount":     "/data",
  "storage_groups":    []
}'

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
