#!/usr/bin/env bash
# =============================================================================
# vm/testing-env-kde-hyprland.sh — VM test: single-disk with KDE + Hyprland
# =============================================================================
# Layout: 1 × 60 GiB SATA disk (/dev/sda)
# Config: mode=single, desktop=["kde","hyprland"], gpu=auto
#         SDDM is the display manager; Hyprland appears as a session
#         greetd is NOT installed (KDE wins DM arbitration)
# =============================================================================

VM_NAME="arch-zfs-test-env-kde-hyprland"
VM_DISK_SIZES=(60)

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "vm-test-env-kde-hyprland",
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
  "environment": {
    "desktop": ["kde", "hyprland"],
    "gpu":     "auto"
  },
  "post_install": {
    "backup":   false,
    "security": false
  },
  "mode":              "single",
  "disk":              "/dev/sda",
  "ashift":            12,
  "os_size":           "50G",
  "os_pool_name":      "rpool",
  "storage_pool_name": "dpool",
  "storage_mount":     "/data",
  "storage_groups":    []
}'

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
