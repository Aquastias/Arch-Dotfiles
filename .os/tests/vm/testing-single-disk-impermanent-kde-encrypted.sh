#!/usr/bin/env bash
# =============================================================================
# vm/testing-single-disk-impermanent-kde-encrypted.sh
#   — VM test: imperm + KDE + ZFS native encryption
# =============================================================================
# Layout: 1 × 40 GiB SATA disk (/dev/sda)
# Config: mode=single, desktop=kde, options.encryption=true,
#         options.impermanence.enabled=true.
#
# Catches the regression where the Rollback Hook runs BEFORE the ZFS
# unlock hook, fails to see the Rollback Datasets, and drops to emergency
# shell. Correct ordering: zfs hook (unlock) → zfs-rollback hook →
# filesystems (mount). Wired by lib/chroot/initcpio.sh.
#
# Encryption prerequisites (operator must supply before running):
#   - The installer prompts for the passphrase on /dev/tty, so the harness
#     cannot drive it automatically. Operator must connect to the VM
#     console (e.g. `virsh console arch-zfs-test-single-impermanent-
#     kde-encrypted`) and type the passphrase when prompted.
#   - At every boot, the same passphrase is required.
#
# Post-install manual verification (harness installs only):
#   - zfs get encryption rpool reports encryption=on
#   - All Rollback Datasets exist with @blank snapshots
#   - First boot: passphrase prompt → unlock → Rollback Hook reverts →
#     filesystems mount → curated persist mounts active
#   - SSH host key persists across reboot
#   - Unpersisted /etc edit vanishes after reboot
#   - SDDM reaches the login screen after reboot
# =============================================================================

VM_NAME="arch-zfs-test-single-impermanent-kde-encrypted"
VM_DISK_SIZES=(40)
VM_RAM_MB=6144

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "vm-test-imp-kde-enc",
    "locale":   "en_US.UTF-8",
    "timezone": "UTC",
    "keymap":   "us"
  },
  "options": {
    "kernel":      "lts",
    "bootloader":  "systemd-boot",
    "encryption":  true,
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
  "environment": {
    "desktop": "kde",
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
