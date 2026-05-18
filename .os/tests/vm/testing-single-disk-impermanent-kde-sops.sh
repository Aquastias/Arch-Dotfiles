#!/usr/bin/env bash
# =============================================================================
# vm/testing-single-disk-impermanent-kde-sops.sh — VM test: imperm + KDE + SOPS
# =============================================================================
# Layout: 1 × 40 GiB SATA disk (/dev/sda)
# Config: mode=single, desktop=kde, options.impermanence.enabled=true,
#         dotfiles_repo + age_key_url set so the post-install secrets phase
#         exercises SOPS.
#
# This is the canary for the SOPS + age-key derivation pipeline under
# impermanence. The Machine Age Key derived from ssh_host_ed25519_key
# survives reboot only because /etc/ssh AND /etc/secrets are both in the
# Curated Persist Defaults.
#
# SOPS prerequisites (operator must supply before running):
#   - DOTFILES_REPO_URL (or REPO_URL): URL of a dotfiles repo with
#     SOPS-encrypted host + user secrets checked in.
#   - AGE_KEY_URL: HTTPS URL of a passphrase-encrypted age key (.age).
#   The harness clones REPO_URL inside the VM; the install consumes
#   age_key_url to decrypt the key, then sops to decrypt secrets.
#
# Post-install manual verification (harness installs only):
#   - /etc/secrets/age/keys.txt bind-mounted from
#     /persist/etc/secrets/age/keys.txt
#   - /etc/ssh/ssh_host_ed25519_key bind-mounted from
#     /persist/etc/ssh/ssh_host_ed25519_key
#   - SOPS Runtime Service decrypts secrets to /run/secrets/ on first boot
#   - After reboot, same secrets decrypt to same plaintext values
#   - ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub output identical
#     before and after reboot
#   - SDDM reaches the login screen after reboot
# =============================================================================

VM_NAME="arch-zfs-test-single-impermanent-kde-sops"
VM_DISK_SIZES=(40)
VM_RAM_MB=6144

: "${DOTFILES_REPO_URL:=${REPO_URL:-}}"
: "${AGE_KEY_URL:=}"

INSTALL_CONFIG_CONTENT=$(cat <<EOF
{
  "system": {
    "hostname": "vm-test-imp-kde-sops",
    "locale":   "en_US.UTF-8",
    "timezone": "UTC",
    "keymap":   "us"
  },
  "dotfiles_repo": "${DOTFILES_REPO_URL}",
  "options": {
    "kernel":      "lts",
    "bootloader":  "systemd-boot",
    "encryption":  false,
    "swap":        true,
    "swap_size":   "auto",
    "esp_size":    "512M",
    "age_key_url": "${AGE_KEY_URL}",
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
}
EOF
)

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
