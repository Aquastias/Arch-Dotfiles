#!/usr/bin/env bash
# =============================================================================
# lib/boot/esp-kernel-sync.sh — ESP Kernel Sync (ADR 0038)
# =============================================================================
# systemd-boot cannot read ZFS, so the kernel image, microcode, and initramfs
# must be copied from the ZFS /boot onto the FAT32 ESP. Installed as a pacman
# PostTransaction hook that fires on every kernel transaction.
#
# The set of files to mirror is driven by the loader entries: the planner emits
# exactly the files the entries reference (their linux/initrd lines) that exist
# in /boot. The entries name only Kernel-Selection kernels and the microcode
# present, so a Stray Kernel — having no entry — is never mirrored, and a
# never-referenced file is never copied. This replaces the old linux* glob.
#
# Sourced lib-only by tests (ESP_KERNEL_SYNC_LIB_ONLY=1) to exercise the pure
# planner without the runtime copy loop (mirrors initcpio.sh's lib-only guard).
# =============================================================================

# Pure: print the /boot filenames referenced by the loader entries under
# <esp_dir>/loader/entries that also exist in <boot_dir>, one per line, sorted
# and de-duplicated.
esp_sync_planned_files() {
  local esp_dir="$1" boot_dir="$2" entry name
  for entry in "$esp_dir"/loader/entries/*.conf; do
    [[ -f "$entry" ]] || continue
    awk '$1 == "linux" || $1 == "initrd" { print $2 }' "$entry"
  done | sed 's#^/##' | sort -u | while IFS= read -r name; do
    [[ -n "$name" && -f "$boot_dir/$name" ]] && printf '%s\n' "$name"
  done
}

# Lib-only sourcing for tests: skip the runtime below.
[[ "${ESP_KERNEL_SYNC_LIB_ONLY:-0}" == "1" ]] && return 0

# Runtime: mirror each planned file from /boot onto every mounted ESP. The
# primary ESP (/boot/efi) holds the loader entries that drive the plan.
_esp_kernel_sync_run() {
  local f d
  while IFS= read -r f; do
    for d in /boot/efi*/; do
      cp "/boot/$f" "$d"
    done
  done < <(esp_sync_planned_files /boot/efi /boot)
}

_esp_kernel_sync_run
