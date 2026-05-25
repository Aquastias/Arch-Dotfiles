#!/usr/bin/env bash
# =============================================================================
# vm/vm-secure.sh — persistent VM: SOPS + impermanence + ZFS encryption
# =============================================================================
# Layout: 2 × 40 GiB SATA disks (/dev/sda, /dev/sdb), mirror rpool
# Config: mode=multi, encryption=on, impermanence=on, headless (no desktop)
#         Bootloader: systemd-boot
#         Test Host:  hosts/vm/arch-secure/  (slice 02 wiring)
#         Test User:  users/vm-test/         (slice 02 wiring)
#
# Exercises the combined Secrets Module + Impermanence install path +
# ZFS native encryption in one shot — none of the other vm/*.sh scripts
# cover all three together.
#
# Test Age Key: .os/vm/fixtures/key.age, passphrase "test".
#   The harness stages key.age into ${CACHE_DIR} via VM_FIXTURE_FILES below,
#   the existing python HTTP server serves it at
#   http://192.168.122.1:9876/key.age, the Secrets Module fetches it during
#   install, and `age --decrypt` prompts on /dev/tty — type `test` at the
#   live-CD prompt when asked.
#
# Manual post-reboot verification checklist (after the VM restarts into
# the installed system, log in as vm-test / vmtest):
#   - zfs list -t snapshot rpool | grep @blank — 5 Rollback Datasets each
#     have a @blank snapshot.
#   - mount | grep /persist — Persist Dataset is mounted.
#   - systemctl status sops-runtime.service — green, decrypted on boot.
#   - ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub — output is
#     byte-identical pre- and post-reboot (confirms host-key persistence).
#   - sudo su -c 'ls /run/secrets/' — decrypted SOPS payloads present.
#
# References:
#   - PRD:  .scratch/vm-secure-smoke-test/PRD.md
#   - ADR:  docs/adr/0019-committed-sops-fixtures-for-vm-smoke-tests.md
# =============================================================================

VM_NAME="arch-secure"
VM_DISK_SIZES=(40 40)
VM_RAM_MB=6144
VM_VCPUS=4

# Stage the Test Age Key into ${CACHE_DIR} so the harness HTTP server
# serves it at http://192.168.122.1:9876/key.age.
VM_FIXTURE_FILES=("fixtures/key.age")

INSTALL_CONFIG_CONTENT='{
  "system": {
    "hostname": "arch-secure",
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
    },
    "age_key_url": "http://192.168.122.1:9876/key.age"
  },
  "packages": { "extra": [], "groups": {} },
  "environment": {
    "desktop": [],
    "gpu":     "auto"
  },
  "post_install": {
    "backup":   false,
    "security": false
  },
  "mode": "multi",
  "os_pool": {
    "topology": "mirror",
    "disks":    ["/dev/sda", "/dev/sdb"],
    "ashift":   12,
    "pool_name": "rpool"
  },
  "ashift":            12,
  "os_size":           "auto",
  "os_pool_name":      "rpool",
  "storage_pool_name": "dpool",
  "storage_mount":     "/data",
  "storage_groups":    []
}'

# shellcheck source=_harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/_harness.sh"
run_harness "$@"
