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
    #   2. packages.extra[] — flat list from config
    #   3. packages.groups.{cli,dev,gui,...}[] — grouped lists from config
    #      (keys starting with "_" are comment fields and are filtered out)
    #
    # Output: one package name per line, sorted and deduplicated.

    local pkgs=(
        # ── Core system ───────────────────────────────────────────────────────
        base
        base-devel
        linux
        linux-headers       # needed by zfs-dkms in the installed system
        linux-firmware

        # ── CPU microcode (both; unused one is harmlessly ignored at boot) ────
        intel-ucode
        amd-ucode

        # ── ZFS ───────────────────────────────────────────────────────────────
        # zfs-dkms compiles the ZFS module against the installed kernel's headers.
        # zfs-utils provides zpool, zfs, and all userspace tools.
        zfs-dkms
        zfs-utils

        # ── Network ───────────────────────────────────────────────────────────
        networkmanager      # handles wired + wireless; enabled in chroot

        # ── Bootloader + EFI tools ────────────────────────────────────────────
        efibootmgr          # manages UEFI boot entries (used for secondary ESPs)
        dosfstools          # mkfs.fat for ESP formatting

        # ── Core utilities ────────────────────────────────────────────────────
        vim
        git
        sudo
        rsync               # used by the ESP mirror pacman hook
        jq                  # used by the installer; handy on the installed system

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
    reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null \
        || warn "reflector failed — using existing mirrorlist."

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

    info "Base system installed."
}
