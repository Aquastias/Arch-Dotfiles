#!/usr/bin/env bash
# =============================================================================
# vm/vm-hyprland.sh — persistent VM: single-disk with Hyprland
# =============================================================================
# Layout: 1 × 40 GiB SATA disk (/dev/sda)
# Config: mode=single, desktop=hyprland, gpu=auto
#         Display manager: greetd + tuigreet
# =============================================================================

VM_NAME="arch-hyprland"
VM_DISK_SIZES=(40)
VM_RAM_MB=6144
VM_VCPUS=4

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "arch-hyprland",
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
    "desktop": "hyprland",
    "gpu":     "auto"
  },
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
