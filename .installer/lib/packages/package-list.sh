#!/usr/bin/env bash
# =============================================================================
# lib/packages/package-list.sh — package collection + base system install
# =============================================================================
# Requires: lib/common.sh already sourced.
#
# Provides:
#   package_list_collect      — merges the Base Package List, the derived sets,
#                               and the Effective Config's packages.repo into a
#                               sorted unique list
#   package_list_install_base — updates mirrorlist, edits the host pacman.conf
#                               (lib/packages/pacman-config.sh), runs pacstrap
#                               with the collected packages
#
# Used by: 03-install.sh (sources it).
# =============================================================================

# package_list_collect parses packages.repo through the Categorized List Parser
# on every call now, so the dependency is explicit rather than assumed of
# callers. shellcheck source=../config/categorized-list.sh
declare -F categorized_list_parse >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/categorized-list.sh"
# shellcheck source=../boot/bootloader.sh
declare -F bootloader_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../boot/bootloader.sh"
# shellcheck source=../config/fonts.sh
declare -F fonts_repo_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/fonts.sh"
# shellcheck source=./base.sh
declare -F base_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/base.sh"
# shellcheck source=./filesystem.sh
declare -F filesystem_userland_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/filesystem.sh"
# shellcheck source=./archzfs-kernel.sh
declare -F archzfs_kernel_lts_pin_prepare >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/archzfs-kernel.sh"
# shellcheck source=./pacman-config.sh
declare -F pacman_config_apply_options >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/pacman-config.sh"

# =============================================================================
# PACKAGE COLLECTION
# =============================================================================

# Builds the full pacstrap package list, merged + deduplicated from: base
# packages, kernel packages (options.kernel, via kernel.sh), bootloader
# packages (options.bootloader), host packages.repo[], and the resolved
# GPU_PACMAN_PACKAGES + AUDIO_PACKAGES. One name per line, sorted-unique.
# The _package_list_add_* steps append to this function's `packages` array
# (dynamic scope).
package_list_collect() {
  environment_resolve

  # Base set from the shared Base Package List (lib/packages/base.sh) — the
  # same names the Package Resolver reports, so install and query cannot
  # drift. The kernel(s)+headers and bootloader package(s) come from their own
  # token tables (kernel.sh / bootloader.sh), also shared with the resolver.
  # CPU microcode, ZFS/LUKS/fs userland, GPU, and audio are appended below,
  # config-conditional.
  local -a packages=()
  mapfile -t packages < <(base_packages)
  _package_list_add_kernels
  _package_list_add_bootloader
  _package_list_add_config_packages
  _package_list_add_zfs_userland
  _package_list_add_filesystem_userland

  # GPU and audio packages resolved by environment_resolve above (ADR 0017)
  packages+=("${GPU_PACMAN_PACKAGES[@]+"${GPU_PACMAN_PACKAGES[@]}"}")
  packages+=("${AUDIO_PACKAGES[@]+"${AUDIO_PACKAGES[@]}"}")

  # CPU microcode — only the running CPU's vendor's package (ADR 0038); empty
  # on a VM / unknown CPU, which then installs no microcode.
  local microcode
  microcode="$(microcode_vendor_package "$(microcode_detect_vendor)")"
  [[ -n "$microcode" ]] && packages+=("$microcode")

  # Sort and deduplicate — pacstrap handles duplicates gracefully but this
  # keeps the output clean and avoids confusion in the install log.
  printf '%s\n' "${packages[@]}" | sort -u
}

# Every selected flavour token (Kernel Selection) is installed with its
# matching headers, mapped through the single token table in
# lib/packages/kernel.sh; headers are needed by zfs-dkms. zfs-dkms builds ZFS
# against whichever headers are present, so one zfs-dkms covers all installed
# kernels (added once, regardless of count).
_package_list_add_kernels() {
  local -a kernel_packages=()
  local token
  while IFS= read -r token; do
    [[ -n "$token" ]] || continue
    kernel_packages+=("$(kernel_package "$token")"
      "$(kernel_headers_package "$token")")
  done < <(install_config_kernels)

  # archzfs LTS ceiling pin (ADR 0137): when archzfs_kernel_lts_pin_prepare had
  # to hold the target linux-lts back, it exported the version-pinned specs.
  # Swap the bare lts token + headers for them so pacstrap installs the
  # archzfs-safe kernel. No-op when unset — the happy path stays
  # byte-identical.
  if [[ -n "${LTS_PIN_SPECS:-}" ]]; then
    local -a pin_specs; read -ra pin_specs <<<"$LTS_PIN_SPECS"
    local i
    for i in "${!kernel_packages[@]}"; do
      case "${kernel_packages[$i]}" in
        linux-lts)         kernel_packages[i]="${pin_specs[0]}" ;;
        linux-lts-headers) kernel_packages[i]="${pin_specs[1]}" ;;
      esac
    done
  fi
  packages+=("${kernel_packages[@]}")
}

# Extra package(s) come from the Bootloader Manifest (ADR 0077). Today:
# systemd-boot adds nothing, grub adds grub (booted from the ESP like the
# others, ADR 0078). efibootmgr (base) registers UEFI entries for both.
_package_list_add_bootloader() {
  local bootloader
  bootloader="$(install_config_bootloader)"
  local -a bootloader_package_names=()
  mapfile -t bootloader_package_names < <(bootloader_packages "$bootloader")
  packages+=("${bootloader_package_names[@]+"${bootloader_package_names[@]}"}")
}

# Host repo packages + the Font Catalog, both from the EFFECTIVE CONFIG.
_package_list_add_config_packages() {
  local config_json package
  config_json="$(jsonc_strip "$CONFIG_FILE")"

  # packages.repo from the EFFECTIVE CONFIG, which already carries the
  # resolved core+profile merge. Reading it here rather than re-loading the
  # committed profile by hostname is what makes all three front-ends agree:
  # the guided and inline-config paths have no hosts/<hostname>/ directory to
  # re-read, so anything they authored (including the extra-packages row) was
  # silently dropped. AUR packages (packages.aur) are handled separately in
  # profiles.sh via paru.
  local repo_json
  repo_json="$(jq -c '.packages.repo // {}' <<<"$config_json")"
  while IFS= read -r package; do
    [[ -n "$package" ]] && packages+=("$package")
  done < <(categorized_list_parse "$repo_json" string "packages.repo")

  # Font Catalog (ADR 0080): fonts moved out of packages.repo into the curated
  # options.fonts catalog — the single font home. Repo fonts feed pacstrap
  # here; AUR fonts (ttf-ms-fonts) ride the Runner's paru pass. Absent
  # options.fonts ⇒ the catalog defaults, so a profile that declares no fonts
  # still gets the set.
  while IFS= read -r package; do
    [[ -n "$package" ]] && packages+=("$package")
  done < <(fonts_repo_packages "$config_json")
  return 0
}

# ZFS userland — only when some group is ZFS (root or a data pool). A pure
# non-ZFS install installs no ZFS packages (ADR 0043). zfs-dkms compiles ZFS
# against the installed kernel headers; zfs-utils provides zpool/zfs.
_package_list_add_zfs_userland() {
  [[ "$(install_config_any_zfs)" == "true" ]] || return 0
  local -a zfs_packages
  read -ra zfs_packages <<<"$(filesystem_userland_packages zfs)"
  # archzfs prebuilt for a pure-lts install (ADR 0137): archzfs's zfs-dkms
  # source fails to build even at the ceiling, but its prebuilt zfs-linux-lts
  # for the pinned linux-lts works. Swap zfs-dkms -> zfs-linux-lts when one is
  # available; the ceiling pin keeps linux-lts at the prebuilt's version.
  local module_package i
  local -a kernels; mapfile -t kernels < <(install_config_kernels)
  module_package="$(archzfs_kernel_lts_module_package "${kernels[@]}")"
  if [[ -n "$module_package" ]]; then
    for i in "${!zfs_packages[@]}"; do
      [[ "${zfs_packages[$i]}" == "zfs-dkms" ]] \
        && zfs_packages[i]="$module_package"
    done
  fi
  packages+=("${zfs_packages[@]}")
}

# LUKS userland for any non-ZFS encrypted group — a non-zfs encrypted root
# (mkinitcpio `encrypt` hook) OR an encrypted ext4/xfs/btrfs data disk
# (boot-time crypttab). ZFS uses its own native crypto so it needs none of
# this (ADR 0043). Then per-filesystem userland for any non-zfs group that
# uses it: xfsprogs (fsck.xfs/mkfs.xfs) for xfs, btrfs-progs
# (fsck.btrfs/mkfs.btrfs) for btrfs — so the data group fscks + mounts at
# boot. ext4 rides e2fsprogs in base; zfs has no mkfs. Independent of
# encryption.
_package_list_add_filesystem_userland() {
  local -a tools
  if [[ "$(install_config_any_nonzfs_luks)" == "true" ]]; then
    read -ra tools <<<"$(filesystem_luks_userland_packages)"
    packages+=("${tools[@]}")
  fi
  local filesystem
  for filesystem in xfs btrfs; do
    [[ "$(install_config_uses_filesystem "$filesystem")" == "true" ]] \
      || continue
    read -ra tools <<<"$(filesystem_userland_packages "$filesystem")"
    packages+=("${tools[@]}")
  done
}

# =============================================================================
# BASE SYSTEM INSTALLATION
# =============================================================================

# package_list_reflector_country_arguments — the `--country <comma-list>` args
# for reflector, built from the Mirror Countries selection (issue 06). Emits one
# arg per line so package_list_install_base can mapfile them into an array.
# Pure: reads config only.
package_list_reflector_country_arguments() {
  local -a countries
  mapfile -t countries < <(install_config_mirror_countries)
  # No countries: no --country, so reflector ranks every mirror (ADR 0157).
  ((${#countries[@]})) || return 0
  local joined; printf -v joined '%s,' "${countries[@]}"
  printf '%s\n' "--country" "${joined%,}"
}

# package_list_prepend_custom_mirror_servers — write the operator's custom
# mirror Servers (ADR 0072) ABOVE the reflector-ranked list, so they are tried
# first. Called after reflector --save so they are not clobbered. No-op when
# none declared.
package_list_prepend_custom_mirror_servers() {
  local -a servers; mapfile -t servers < <(install_config_mirror_servers)
  ((${#servers[@]})) || return 0
  local mirrorlist=/etc/pacman.d/mirrorlist server merged_file
  merged_file="$(mktemp)"
  { printf '# Custom mirror servers (guided installer)\n'
    for server in "${servers[@]}"; do
      [[ -n "$server" ]] && printf 'Server = %s\n' "$server"
    done
    printf '\n'; cat "$mirrorlist" 2>/dev/null; } > "$merged_file"
  mv "$merged_file" "$mirrorlist"
  info "Prepended ${#servers[@]} custom mirror server(s)."
}

package_list_install_base() {
  section "Installing Base System (pacstrap)"
  _package_list_refresh_mirrors
  _package_list_prepare_pacman_config

  local -a packages
  mapfile -t packages < <(package_list_collect)
  info "Packages to install: ${#packages[@]}"

  # pacstrap flags:
  #   -K       — initialise a fresh pacman keyring inside the chroot (required
  #              for signature verification of newly installed packages)
  #   --needed — skip packages that are already installed in the target
  #              (guards against re-installing if pacstrap is re-run)
  # Retried: one mirror/CDN blip (e.g. a GitHub-hosted archzfs file) must not
  # end a whole install; --needed makes a re-run resume, not redo.
  _retry 3 "10,30" -- pacstrap -K "${MOUNT_ROOT}" --needed "${packages[@]}"

  # archzfs LTS ceiling pin (ADR 0137): the temporary [archzfs-lts-pin] local
  # repo was only needed for this pacstrap transaction. Remove it now from both
  # the host conf (so chroot.sh's copy is clean) and the target's copy
  # (pacstrap already copied pacman.conf in) — left in place it breaks `pacman
  # -Sy`/`-Fy` later, since the local repo dir is not in the target. No-op
  # when unpinned.
  if [[ -n "${LTS_PIN_SPECS:-}" ]]; then
    archzfs_kernel_lts_pin_cleanup /etc/pacman.conf
    archzfs_kernel_lts_pin_cleanup "${MOUNT_ROOT}/etc/pacman.conf"
  fi

  _package_list_clean_target_cache
  _package_list_init_target_keyring
  info "Base system installed."
}

# Refresh mirrorlist with the fastest mirrors near the operator (Mirror
# Countries) — non-fatal if reflector fails (e.g. offline).
_package_list_refresh_mirrors() {
  info "Updating mirror list..."
  local -a country_arguments
  mapfile -t country_arguments < <(package_list_reflector_country_arguments)
  reflector "${country_arguments[@]}" --latest 10 --sort rate \
    --save /etc/pacman.d/mirrorlist 2>/dev/null ||
    warn "reflector failed — using existing mirrorlist."
  # Operator's custom mirror servers go above the ranked list (ADR 0072).
  package_list_prepend_custom_mirror_servers
}

# Host pacman.conf edits pacstrap must see (and the target inherits).
_package_list_prepare_pacman_config() {
  # Enable the selected Optional Repositories (multilib + testing) and add any
  # custom repositories before pacstrap runs (ADR 0072).
  pacman_config_enable_optional_repositories
  pacman_config_add_custom_repositories

  # Apply the operator's Pacman Options (ADR 0074) to the host pacman.conf
  # before pacstrap, so Color / ParallelDownloads / ILoveCandy act during base
  # install too and the target inherits them via chroot.sh's pacman.conf copy.
  pacman_config_apply_options
  pacman_config_apply_audit_cache   # test-only (Feature Audit); no-op otherwise

  # ZFS reports space in a way pacman's CheckSpace can't read — disable it so
  # pacstrap (and later upgrades) don't abort with a false "too full".
  pacman_config_disable_checkspace

  # archzfs LTS ceiling (ADR 0137): before pacstrap, pin the target linux-lts
  # to a version archzfs can build ZFS against. No-op unless the mirror's
  # linux-lts has outrun archzfs. Only when some group is ZFS and lts is
  # selected — the only flavour the pin covers.
  if [[ "$(install_config_any_zfs)" == "true" ]] \
     && install_config_kernels | grep -qx lts; then
    archzfs_kernel_lts_pin_prepare
  fi
}

# Clean the package cache inside the new root — downloaded .pkg.tar.zst files
# are no longer needed after install and take ~500 MB–1.5 GB. Keep 0 cached
# versions (keep=0 removes everything). Test-only INSTALL_PKG_CACHE_KEEP: the
# Feature Audit harvests the base variant's packages into the Audit Cache, then
# clears them itself.
_package_list_clean_target_cache() {
  local cache_directory="${MOUNT_ROOT}/var/cache/pacman/pkg/"
  if [[ -z "${INSTALL_PKG_CACHE_KEEP:-}" ]]; then
    info "Cleaning pacman package cache..."
    # Remove all cached packages directly — no need to enter chroot.
    # paccache would work too but requires the chroot to be fully set up.
    rm -f "$cache_directory"*.pkg.tar.zst \
      "$cache_directory"*.pkg.tar.xz \
      "$cache_directory"*.pkg.tar.gz \
      "$cache_directory"*.pkg.tar 2>/dev/null || true
    info "Package cache cleared" \
         "($(du -sh "$cache_directory" 2>/dev/null \
            | awk '{ print $1 }') remaining)."
  fi

  # Configure pacman to keep only 1 cached version going forward
  # (prevents cache from growing unbounded after updates)
  if ! grep -q '^CleanMethod' "${MOUNT_ROOT}/etc/pacman.conf" 2>/dev/null; then
    sed -i 's/^#CleanMethod.*/CleanMethod = KeepCurrent/' \
      "${MOUNT_ROOT}/etc/pacman.conf" 2>/dev/null || true
  fi
}

# pacstrap -K initialises the keyring but gpg-agent state can be stale by the
# time paru runs inside arch-chroot. Re-init and populate explicitly so pacman
# signature checks work reliably during profile installs.
_package_list_init_target_keyring() {
  info "Initialising pacman keyring inside chroot..."
  arch-chroot "${MOUNT_ROOT}" pacman-key --init
  arch-chroot "${MOUNT_ROOT}" pacman-key --populate archlinux
}
