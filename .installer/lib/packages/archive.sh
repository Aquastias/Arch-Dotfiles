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
#   kver_to_pkgver <kver>                        kernel release → pkgver (pure)
#   pkg_archive_url <pkg> <pkgver> [arch]        archive URL (pure)
#   pkg_fetch_from_archive <pkg> <pkgver> <dest> [arch]   download only
#   pkg_ensure_version <pkg> <pkgver> [arch]     install exact, mirror→archive
# =============================================================================

# Guard against double-sourcing.
[[ -n "${_PACKAGES_ARCHIVE_SH_SOURCED:-}" ]] && return 0
_PACKAGES_ARCHIVE_SH_SOURCED=1

# Arch kernel release strings look like 6.19.10-arch1-1; the matching package
# version is 6.19.10.arch1-1 — the hyphen before "arch" becomes a dot. Pure.
kver_to_pkgver() { printf '%s\n' "${1/-arch/.arch}"; }

# Archive URL for an EXACT package version. archive.archlinux.org lays packages
# out under the first letter of the package name. Pure; defaults to x86_64.
pkg_archive_url() {
  local pkg="$1" pkgver="$2" arch="${3:-x86_64}"
  local file="${pkg}-${pkgver}-${arch}.pkg.tar.zst"
  printf 'https://archive.archlinux.org/packages/%s/%s/%s\n' \
    "${pkg:0:1}" "$pkg" "$file"
}

# Download an exact package version from the archive to <dest>. Non-zero on
# failure — the caller decides whether that is fatal.
pkg_fetch_from_archive() {
  local pkg="$1" pkgver="$2" dest="$3" arch="${4:-x86_64}"
  local url
  url="$(pkg_archive_url "$pkg" "$pkgver" "$arch")"
  info "Downloading ${pkg}=${pkgver} from Arch Linux Archive ..."
  curl -fL --progress-bar "$url" -o "$dest"
}

# Ensure an EXACT <pkg>=<pkgver> is installed on the RUNNING system: try the
# current mirror first, then the archive (pacman -U). Non-zero if both fail.
pkg_ensure_version() {
  local pkg="$1" pkgver="$2" arch="${3:-x86_64}"

  if pacman -S --noconfirm --needed "${pkg}=${pkgver}" 2>/dev/null; then
    return 0
  fi

  warn "${pkg}=${pkgver} not on mirror — falling back to Arch Linux Archive ..."
  local tmp="${TMPDIR:-/tmp}/${pkg}-${pkgver}-${arch}.pkg.tar.zst"
  pkg_fetch_from_archive "$pkg" "$pkgver" "$tmp" "$arch" || return 1
  pacman -U --noconfirm "$tmp"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}
