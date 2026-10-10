#!/usr/bin/env bash
# =============================================================================
# lib/packages/archive.sh — Arch Linux Archive package fetch (Installer Stdlib)
# =============================================================================
# One implementation of "get an EXACT package version", shared by:
#   - lib/zfs/module.sh — the exact live-ISO kernel headers for the DKMS build
#   - lib/packages/*    — pinning the target linux-lts to the archzfs LTS
#                         ceiling when the mirror has moved past it (ADR 0137)
#
# The current mirror only carries the newest version of a package; older exact
# versions live forever on archive.archlinux.org. These helpers try the mirror
# first and fall back to the archive.
#
# Requires: lib/common.sh already sourced (info/warn). curl, pacman.
#
# Provides:
#   archive_kernel_version_to_package_version <kver>
#       kernel release → pkgver (pure)
#   archive_package_url <package> <pkgver> [arch]          archive URL (pure)
#   archive_fetch_package <package> <pkgver> <dest> [arch] download only
#   archive_ensure_package_version <package> <pkgver> [arch]
#       install exact, mirror→archive
#
# Used by: lib/zfs/module.sh, lib/packages/archzfs-kernel.sh (both host and
# chroot; staged by lib/chroot.sh).
# =============================================================================

# Guard against double-sourcing.
[[ -n "${_PACKAGES_ARCHIVE_SH_SOURCED:-}" ]] && return 0
_PACKAGES_ARCHIVE_SH_SOURCED=1

# Arch kernel release strings look like 6.19.10-arch1-1; the matching package
# version is 6.19.10.arch1-1 — the hyphen before "arch" becomes a dot. Pure.
archive_kernel_version_to_package_version() {
  printf '%s\n' "${1/-arch/.arch}"
}

# Archive URL for an EXACT package version. archive.archlinux.org lays packages
# out under the first letter of the package name. Pure; defaults to x86_64.
archive_package_url() {
  local package="$1" pkgver="$2" arch="${3:-x86_64}"
  local file="${package}-${pkgver}-${arch}.pkg.tar.zst"
  printf 'https://archive.archlinux.org/packages/%s/%s/%s\n' \
    "${package:0:1}" "$package" "$file"
}

# Download an exact package version from the archive to <dest>. Non-zero on
# failure — the caller decides whether that is fatal.
archive_fetch_package() {
  local package="$1" pkgver="$2" dest="$3" arch="${4:-x86_64}"
  local url
  url="$(archive_package_url "$package" "$pkgver" "$arch")"
  info "Downloading ${package}=${pkgver} from Arch Linux Archive ..."
  curl -fL --progress-bar "$url" -o "$dest"
}

# Ensure an EXACT <pkg>=<pkgver> is installed on the RUNNING system: try the
# current mirror first, then the archive (pacman -U). Non-zero if both fail.
archive_ensure_package_version() {
  local package="$1" pkgver="$2" arch="${3:-x86_64}"

  if pacman -S --noconfirm --needed "${package}=${pkgver}" 2>/dev/null; then
    return 0
  fi

  warn "${package}=${pkgver} not on mirror —" \
    "falling back to Arch Linux Archive ..."
  local package_file
  package_file="${TMPDIR:-/tmp}/${package}-${pkgver}-${arch}.pkg.tar.zst"
  archive_fetch_package "$package" "$pkgver" "$package_file" "$arch" \
    || return 1
  pacman -U --noconfirm "$package_file"
  local rc=$?
  rm -f "$package_file"
  return "$rc"
}
