#!/usr/bin/env bash
# =============================================================================
# lib/packages/list.sh — Package collection and base system installation
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   collect_packages — merges base + config extra/groups into a
#                      sorted unique list
#   install_base — updates mirrorlist, runs pacstrap with
#                  collected packages
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
  #   3. Bootloader packages — selected by options.bootloader in the profile
  #   4. packages.extra[] — flat list from the host profile
  #   5. packages.groups.{cli,dev,gui,...}[] — grouped lists from the profile
  #      (keys starting with "_" are comment fields and are filtered out)
  #   6. Host packages.repo[] — repo packages from the merged host
  #                            config
  #   7. GPU_PACMAN_PACKAGES — resolved by resolve_environment()
  #   8. AUDIO_PACKAGES — resolved by resolve_environment()
  #
  # Output: one package name per line, sorted and deduplicated.
  resolve_environment

  # ── Kernel selection ──────────────────────────────────────────────────────
  # Every selected flavour token (Kernel Selection) is installed with its
  # matching headers, mapped through the single token table in lib/packages/kernel.sh.
  # zfs-dkms builds ZFS against whichever headers are present, so one zfs-dkms
  # covers all installed kernels (added once below, regardless of count).
  local kernel_pkgs=() tok
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    kernel_pkgs+=("$(kernel_pkg "$tok")" "$(kernel_headers_pkg "$tok")")
  done < <(install_config_kernels)

  # ── Bootloader selection ──────────────────────────────────────────────────
  local bootloader
  bootloader="$(install_config_bootloader)"
  local bootloader_pkgs=()
  if [[ "$bootloader" == "grub" ]]; then
    # grub ships the zfs.mod and boots ZFS pools natively — no extra repo pkg.
    # (grub-zfs-config does NOT exist in any repo.) grub-mkconfig runs with
    # ZPOOL_VDEV_NAME_PATH=YES in the bootloader adapter so grub-probe resolves
    # the ZFS root without grub-libzfs — see lib/chroot/bootloader-grub.sh.
    bootloader_pkgs=(grub)
  fi
  # systemd-boot ships with systemd (already in base); no extra package needed.
  # efibootmgr is needed by both to register UEFI boot entries.

  local pkgs=(
    # ── Core system ───────────────────────────────────────────────────────
    base
    base-devel
    "${kernel_pkgs[@]}" # kernel(s) + headers; headers needed by zfs-dkms
    linux-firmware

    # ── CPU microcode ─────────────────────────────────────────────────────
    # Resolved per CPU vendor below (ADR 0038), not hardcoded to both.

    # ── ZFS ───────────────────────────────────────────────────────────────
    # zfs-dkms: compiles ZFS against the installed kernel headers.
    #   For linux-lts this is very reliable — the LTS kernel rarely outpaces
    #   archzfs, unlike the rolling linux kernel which often does.
    # zfs-utils: provides zpool, zfs, and all ZFS userspace commands.
    zfs-dkms
    zfs-utils

    # ── Network ───────────────────────────────────────────────────────────
    networkmanager # handles wired + wireless; enabled in chroot
    openssh        # ssh-keygen used by create-user.sh + sops setup

    # ── Universal infrastructure ──────────────────────────────────────────
    cronie # cron daemon; enabled in chroot (ADR 0026) — every host needs it

    # ── Bootloader + EFI tools ────────────────────────────────────────────
    efibootmgr # manages UEFI boot entries
    dosfstools # mkfs.fat for ESP formatting
    "${bootloader_pkgs[@]+"${bootloader_pkgs[@]}"}"

    # ── Core utilities ────────────────────────────────────────────────────
    vim
    git
    sudo
    rsync          # used by the ESP mirror pacman hook
    jq             # used by the installer; handy on the installed system
    pacman-contrib # provides paccache for package cache management

    # ── Documentation ─────────────────────────────────────────────────────
    man-db
    man-pages
    texinfo
  )

  # ── User-defined flat extra list ──────────────────────────────────────────
  while IFS= read -r p; do
    [[ -n "$p" ]] && pkgs+=("$p")
  done < <(install_config_packages_extra)

  # ── User-defined groups ───────────────────────────────────────────────────
  while IFS= read -r p; do
    [[ -n "$p" ]] && pkgs+=("$p")
  done < <(install_config_packages_groups)

  # ── Host repo packages ─────────────────────────────────────────────────────
  # packages.repo[] from the merged host profile (host core + host-specific).
  # AUR packages (packages.aur[]) are handled separately in profiles.sh
  # via paru.
  if [[ -n "${RESOLVED_HOST_PROFILE:-}" ]]; then
    local host_json host_rc=0
    host_json="$(load_profile "$RESOLVED_HOST_PROFILE" 2>/dev/null)" \
      || host_rc=$?
    if [[ $host_rc -eq 0 || $host_rc -eq 1 ]]; then
      local repo_json
      repo_json="$(printf '%s' "$host_json" \
        | jq -c '.packages.repo // {}')"
      while IFS= read -r p; do
        [[ -n "$p" ]] && pkgs+=("$p")
      done < <(categorized_list_parse "$repo_json" string "packages.repo")
    fi
  fi

  # GPU and audio packages resolved during validate_install_context
  pkgs+=("${GPU_PACMAN_PACKAGES[@]+"${GPU_PACMAN_PACKAGES[@]}"}")
  pkgs+=("${AUDIO_PACKAGES[@]+"${AUDIO_PACKAGES[@]}"}")

  # CPU microcode — only the running CPU's vendor's package (ADR 0038); empty
  # on a VM / unknown CPU, which then installs no microcode.
  local _ucode
  _ucode="$(microcode_vendor_package "$(microcode_detect_vendor)")"
  [[ -n "$_ucode" ]] && pkgs+=("$_ucode")

  # Sort and deduplicate — pacstrap handles duplicates gracefully but this
  # keeps the output clean and avoids confusion in the install log.
  printf '%s\n' "${pkgs[@]}" | sort -u
}

# =============================================================================
# BASE SYSTEM INSTALLATION
# =============================================================================

enable_multilib() {
  # Operator opt-out (issue 06): options.multilib=false leaves [multilib]
  # commented out (the live-ISO default), so the installed system has no
  # multilib. Gate first — before any pacman.conf touch. Defaults to true.
  if [[ "$(install_config_multilib)" != "true" ]]; then
    info "[multilib] disabled by config — skipping."
    return 0
  fi
  # The Arch live ISO ships [multilib] commented out, but lib32-* packages
  # (steam, lib32-nvidia-utils, lib32-gamemode) live there. pacstrap reads the
  # HOST /etc/pacman.conf, so multilib must be enabled here or those targets
  # error as "target not found". configure_system (chroot.sh) later copies this
  # pacman.conf into the new root, so the installed system inherits multilib for
  # future lib32 updates. Idempotent.
  if grep -q '^\[multilib\]' /etc/pacman.conf; then
    info "[multilib] repo already enabled."
    return 0
  fi
  info "Enabling [multilib] repository..."
  # Uncomment the [multilib] header and its adjacent Include line. The range is
  # anchored on '#[multilib]' (not '#[multilib-testing]', which lacks the ']').
  sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
  grep -q '^\[multilib\]' /etc/pacman.conf \
    || error "Failed to enable [multilib] in /etc/pacman.conf."
  pacman -Sy --noconfirm >/dev/null 2>&1 || true
}

disable_checkspace() {
  # pacman's CheckSpace mis-estimates free space on ZFS: it rounds every file
  # up to the dataset recordsize (128K), inflating the "needed" total several-
  # fold, so pacstrap aborts "Partition /mnt too full" even with gigabytes
  # free (e.g. a 20G OS disk after an 8G swap zvol — ~9G free, but ~10G
  # "needed" for a 2.3G install). pacstrap reads the HOST /etc/pacman.conf and
  # chroot.sh copies it into the new root, so disabling it here also spares the
  # installed ZFS system the same false failure on every future pacman -Syu.
  # Idempotent.
  if grep -q '^CheckSpace' /etc/pacman.conf; then
    info "Disabling pacman CheckSpace (unreliable on ZFS)..."
    sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
  else
    info "pacman CheckSpace already disabled."
  fi
}

# reflector_country_args — the `--country <comma-list>` args for reflector,
# built from the Mirror Countries selection (issue 06). Emits one arg per line
# so install_base can mapfile them into an array. Pure: reads config only.
reflector_country_args() {
  local -a countries
  mapfile -t countries < <(install_config_mirror_countries)
  local joined; printf -v joined '%s,' "${countries[@]}"
  printf '%s\n' "--country" "${joined%,}"
}

install_base() {
  section "Installing Base System (pacstrap)"

  # Refresh mirrorlist with the fastest mirrors near the operator (Mirror
  # Countries) — non-fatal if reflector fails (e.g. offline).
  info "Updating mirror list..."
  local -a _country_args
  mapfile -t _country_args < <(reflector_country_args)
  reflector "${_country_args[@]}" --latest 10 --sort rate \
    --save /etc/pacman.d/mirrorlist 2>/dev/null ||
    warn "reflector failed — using existing mirrorlist."

  # lib32-* / steam packages need [multilib] enabled before pacstrap runs.
  enable_multilib

  # ZFS reports space in a way pacman's CheckSpace can't read — disable it so
  # pacstrap (and later upgrades) don't abort with a false "too full".
  disable_checkspace

  mapfile -t pkgs < <(collect_packages)
  info "Packages to install: ${#pkgs[@]}"

  # pacstrap flags:
  #   -K       — initialise a fresh pacman keyring inside the chroot (required
  #              for signature verification of newly installed packages)
  #   --needed — skip packages that are already installed in the target
  #              (guards against re-installing if pacstrap is re-run)
  #
  # "${pkgs[@]}" is properly quoted: each array element becomes its own arg
  # to pacstrap. Package names never contain whitespace, so even unquoted
  # would be safe — quoted is the shellcheck-clean idiom (no SC2068 disable
  # needed).
  pacstrap -K "${MOUNT_ROOT}" --needed "${pkgs[@]}"

  # Clean the package cache inside the new root — downloaded .pkg.tar.zst
  # files are no longer needed after install and take ~500 MB–1.5 GB.
  # Keep 0 cached versions (keep=0 removes everything).
  info "Cleaning pacman package cache..."
  # Remove all cached packages directly — no need to enter chroot.
  # paccache would work too but requires the chroot to be fully set up.
  rm -f "${MOUNT_ROOT}/var/cache/pacman/pkg/"*.pkg.tar.zst \
    "${MOUNT_ROOT}/var/cache/pacman/pkg/"*.pkg.tar.xz \
    "${MOUNT_ROOT}/var/cache/pacman/pkg/"*.pkg.tar.gz \
    "${MOUNT_ROOT}/var/cache/pacman/pkg/"*.pkg.tar 2>/dev/null || true
  info "Package cache cleared" \
       "($(du -sh "${MOUNT_ROOT}/var/cache/pacman/pkg/" 2>/dev/null \
          | cut -f1) remaining)."

  # Configure pacman to keep only 1 cached version going forward
  # (prevents cache from growing unbounded after updates)
  if ! grep -q '^CleanMethod' "${MOUNT_ROOT}/etc/pacman.conf" 2>/dev/null; then
    sed -i 's/^#CleanMethod.*/CleanMethod = KeepCurrent/' \
      "${MOUNT_ROOT}/etc/pacman.conf" 2>/dev/null || true
  fi


  # pacstrap -K initialises the keyring but gpg-agent state can be stale by
  # the time paru runs inside arch-chroot. Re-init and populate explicitly so
  # pacman signature checks work reliably during profile installs.
  info "Initialising pacman keyring inside chroot..."
  arch-chroot "${MOUNT_ROOT}" pacman-key --init
  arch-chroot "${MOUNT_ROOT}" pacman-key --populate archlinux

  info "Base system installed."
}
