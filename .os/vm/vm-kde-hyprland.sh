#!/usr/bin/env bash
# =============================================================================
# vm/vm-kde-hyprland.sh — persistent VM: single-disk with KDE + Hyprland
# =============================================================================
# Layout: 1 × 80 GiB SATA disk (/dev/sda)
# Config: mode=single, desktop=["kde","hyprland"], gpu=auto
#         Display manager: SDDM (greetd not installed — KDE wins arbitration)
#         Hyprland appears as a session in SDDM
# =============================================================================

VM_NAME="arch-kde-hyprland"
VM_DISK_SIZES=(80)
VM_RAM_MB=8192
VM_VCPUS=4

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "arch-kde-hyprland",
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
  "os_size":           "70G",
  "os_pool_name":      "rpool",
  "storage_pool_name": "dpool",
  "storage_mount":     "/data",
  "storage_groups":    []
}'

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
