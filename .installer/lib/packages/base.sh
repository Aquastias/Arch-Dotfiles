#!/usr/bin/env bash
# =============================================================================
# lib/packages/base.sh — Base Package List (single source of truth)
# =============================================================================
# The always-installed set, independent of every config choice. One table here
# drives package install (host-side, lib/packages/list.sh's collect_packages)
# and the Package Resolver's query (lib/packages/resolver.sh's base source), so
# the two can never disagree on what "base" is. Kernel, bootloader, and every
# derived set live with their own concern; this is only the unconditional core.
# =============================================================================

[[ -n "${_BASE_SH_SOURCED:-}" ]] && return 0
_BASE_SH_SOURCED=1

# base_packages — the unconditional base set, one package per line.
#   base/base-devel     the toolchain (base-devel needed for AUR builds)
#   linux-firmware      device firmware blobs
#   networkmanager      wired + wireless; enabled in chroot
#   openssh             ssh-keygen for create-user.sh + sops setup
#   cronie              cron daemon; every host enables it (ADR 0026)
#   efibootmgr/dosfstools  UEFI entries + mkfs.fat for the ESP
#   vim git sudo rsync jq pacman-contrib stow  installer + runtime utilities
#   man-db man-pages texinfo  documentation
base_packages() {
  printf '%s\n' \
    base base-devel linux-firmware networkmanager openssh cronie \
    efibootmgr dosfstools vim git sudo rsync jq pacman-contrib stow \
    man-db man-pages texinfo
}
