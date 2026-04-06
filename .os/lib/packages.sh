#!/usr/bin/env bash
# =============================================================================
# lib/packages.sh — Package collection and base system installation
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   collect_packages  — merges base + config extra/groups into a sorted unique list
#   install_base      — updates mirrorlist, runs pacstrap with collected packages
# =============================================================================

# =============================================================================
# PACKAGE COLLECTION
# =============================================================================

collect_packages() {
  # Builds the full package list to install via pacstrap.
  #
  # Sources (merged and deduplicated):
  #   1. Base packages — always installed regardless of config
  #   2. Kernel packages — selected by options.kernel in config
  #      'lts'     → linux-lts + linux-lts-headers  (recommended, always
  #                  supported by archzfs, moves slowly)
  #      'default' → linux + linux-headers           (latest rolling kernel,
  #                  may temporarily be unsupported by archzfs)
  #   3. Bootloader packages — selected by options.bootloader in config
  #   4. packages.extra[] — flat list from config
  #   5. packages.groups.{cli,dev,gui,...}[] — grouped lists from config
  #      (keys starting with "_" are comment fields and are filtered out)
  #
  # Output: one package name per line, sorted and deduplicated.

  # ── Kernel selection ──────────────────────────────────────────────────────
  local kernel
  kernel="$(cfgo '.options.kernel')"
  kernel="${kernel:-lts}"
  local kernel_pkg kernel_headers_pkg zfs_pkg
  if [[ "$kernel" == "lts" ]]; then
    kernel_pkg="linux-lts"
    kernel_headers_pkg="linux-lts-headers"
    # zfs-dkms works for both kernels; zfs-linux-lts is the pre-built
    # option but zfs-dkms will build against whichever headers are present.
    zfs_pkg="zfs-dkms"
  else
    kernel_pkg="linux"
    kernel_headers_pkg="linux-headers"
    zfs_pkg="zfs-dkms"
  fi

  # ── Bootloader selection ──────────────────────────────────────────────────
  local bootloader
  bootloader="$(cfgo '.options.bootloader')"
  bootloader="${bootloader:-systemd-boot}"
  local bootloader_pkgs=()
  if [[ "$bootloader" == "grub" ]]; then
    # grub-zfs-config-grub2 provides ZFS-aware GRUB setup via grub-mkconfig.
    # grub handles ZFS pools natively — no separate zfs module needed.
    bootloader_pkgs=(grub grub-zfs-config)
  fi
  # systemd-boot ships with systemd (already in base); no extra package needed.
  # efibootmgr is needed by both to register UEFI boot entries.

  local pkgs=(
    # ── Core system ───────────────────────────────────────────────────────
    base
    base-devel
    "$kernel_pkg"
    "$kernel_headers_pkg" # needed by zfs-dkms to build against on updates
    linux-firmware

    # ── CPU microcode (both; unused one is harmlessly ignored at boot) ────
    intel-ucode
    amd-ucode

    # ── ZFS ───────────────────────────────────────────────────────────────
    # zfs-dkms: compiles ZFS against the installed kernel headers.
    #   For linux-lts this is very reliable — the LTS kernel rarely outpaces
    #   archzfs, unlike the rolling linux kernel which often does.
    # zfs-utils: provides zpool, zfs, and all ZFS userspace commands.
    "$zfs_pkg"
    zfs-utils

    # ── Network ───────────────────────────────────────────────────────────
    networkmanager # handles wired + wireless; enabled in chroot

    # ── Bootloader + EFI tools ────────────────────────────────────────────
    efibootmgr # manages UEFI boot entries
    dosfstools # mkfs.fat for ESP formatting
    "${bootloader_pkgs[@]+"${bootloader_pkgs[@]}"}"

    # ── Core utilities ────────────────────────────────────────────────────
    vim
    git
    sudo
    rsync # used by the ESP mirror pacman hook
    jq    # used by the installer; handy on the installed system

    # ── Documentation ─────────────────────────────────────────────────────
    man-db
    man-pages
    texinfo
  )

  # ── User-defined flat extra list ──────────────────────────────────────────
  while IFS= read -r p; do
    [[ -n "$p" ]] && pkgs+=("$p")
  done < <(jq -r '.packages.extra[]? // empty' "$CONFIG_FILE" 2>/dev/null)

  # ── User-defined groups ───────────────────────────────────────────────────
  # Filter out keys starting with "_" (they are inline comment fields, not
  # real package group keys). Only process values that are arrays.
  while IFS= read -r p; do
    [[ -n "$p" ]] && pkgs+=("$p")
  done < <(jq -r '
        .packages.groups // {}
        | to_entries[]?
        | select(.key | startswith("_") | not)
        | select(.value | type == "array")
        | .value[]?
    ' "$CONFIG_FILE" 2>/dev/null)

  # Sort and deduplicate — pacstrap handles duplicates gracefully but this
  # keeps the output clean and avoids confusion in the install log.
  printf '%s\n' "${pkgs[@]}" | sort -u
}

# =============================================================================
# BASE SYSTEM INSTALLATION
# =============================================================================

install_base() {
  section "Installing Base System (pacstrap)"

  # Refresh mirrorlist with the fastest mirrors (non-fatal if reflector fails)
  info "Updating mirror list..."
  reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null ||
    warn "reflector failed — using existing mirrorlist."

  mapfile -t pkgs < <(collect_packages)
  info "Packages to install: ${#pkgs[@]}"

  # pacstrap flags:
  #   -K  — initialise a fresh pacman keyring inside the chroot (required for
  #          signature verification of newly installed packages)
  #   --needed — skip packages that are already installed in the target
  #              (guards against re-installing if pacstrap is re-run)
  #
  # Note: ${pkgs[@]} is intentionally unquoted so each element becomes a
  # separate argument to pacstrap, not a single quoted string.
  # shellcheck disable=SC2068
  pacstrap -K "${MOUNT_ROOT}" --needed ${pkgs[@]}

  # Clean the package cache inside the new root — downloaded .pkg.tar.zst
  # files are no longer needed after install and take ~500 MB–1.5 GB.
  # Keep 0 cached versions (keep=0 removes everything).
  info "Cleaning pacman package cache..."
  arch-chroot "${MOUNT_ROOT}" paccache -rk0 --noconfirm 2>/dev/null || rm -rf "${MOUNT_ROOT}/var/cache/pacman/pkg/"*.pkg.tar.* 2>/dev/null || true

  # Configure pacman to keep only 1 cached version going forward
  # (prevents cache from growing unbounded after updates)
  if ! grep -q '^CleanMethod' "${MOUNT_ROOT}/etc/pacman.conf" 2>/dev/null; then
    sed -i 's/^#CleanMethod.*/CleanMethod = KeepCurrent/' "${MOUNT_ROOT}/etc/pacman.conf" 2>/dev/null || true
  fi

  info "Base system installed."
}
