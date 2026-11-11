#!/usr/bin/env bash
# =============================================================================
# lib/boot/esp-kernel-sync-install.sh — install-time half of the ESP Kernel
# Sync (ADR 0038, ADR 0166): the three pacman hook texts and the one install
# path that writes them with the sync script.
# =============================================================================
# Used by: lib/boot/esp-kernel-sync.sh (sourced in its lib-only mode, which
# lib/chroot/bootloader-common.sh, tools/harden-boot.sh and the tests use).
# The target runs esp-kernel-sync.sh alone; it never needs this file.

# esp_kernel_sync_previous_hook — the pacman hook refreshing previous pairs
# before every transaction. Single source for the installer and the retrofit.
esp_kernel_sync_previous_hook() {
  cat <<'HOOK'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Operation = Remove
Target = *

[Action]
Description = Keeping the previous kernel on the ESP...
When = PreTransaction
Exec = /usr/local/lib/archzfs/esp-kernel-sync.sh previous
HOOK
}

# esp_kernel_sync_preflight_hook / esp_kernel_sync_sync_hook — the kernel-path
# hooks around a kernel transaction: the fail-closed preflight and the sync.
esp_kernel_sync_preflight_hook() {
  cat <<'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Checking ESP free space for new boot images...
When = PreTransaction
Exec = /usr/local/lib/archzfs/esp-kernel-sync.sh preflight
AbortOnFail
HOOK
}

esp_kernel_sync_sync_hook() {
  cat <<'HOOK'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Operation = Remove
Target = *

[Action]
Description = Syncing kernel and initramfs to ESP...
When = PostTransaction
Exec = /usr/local/lib/archzfs/esp-kernel-sync.sh
HOOK
}

# esp_kernel_sync_install <root> <source-script> — install this script and its
# three hooks under <root> ("" = /). The one install path for the installer
# and the retrofit. pacman runs hooks by filename, and 60-mkinitcpio-remove
# (PreTransaction) deletes the /boot images: the preflight (01-) and the
# previous-pair refresh (03-) must run before it. The old, too-late 93-/91-
# names are removed (ADR 0166).
esp_kernel_sync_install() {
  local root source_script="$2" hooks
  root="$(esp_kernel_sync_without_slash "$1")"
  hooks="$root/etc/pacman.d/hooks"
  install -Dm755 "$source_script" \
    "$root/usr/local/lib/archzfs/esp-kernel-sync.sh"
  mkdir -p "$hooks"
  rm -f "$hooks/93-esp-kernel-sync-preflight.hook" \
    "$hooks/91-esp-previous-pair.hook"
  esp_kernel_sync_preflight_hook >"$hooks/01-esp-kernel-sync-preflight.hook"
  esp_kernel_sync_previous_hook >"$hooks/03-esp-previous-pair.hook"
  esp_kernel_sync_sync_hook >"$hooks/94-esp-kernel-sync.hook"
}

