#!/usr/bin/env bash
# =============================================================================
# lib/packages/archzfs-kernel.sh — the archzfs LTS Ceiling (ADR 0137)
# =============================================================================
# Single owner of "which linux-lts is archzfs-safe". The target install DKMS-
# builds ZFS against whatever linux-lts pacstrap pulls from the always-current
# Arch core mirror; archzfs's zfs-dkms source lags on its own cadence. When the
# mirror's linux-lts MINOR outruns what the ZFS source supports the DKMS build
# fails to compile (the intermittent `BIO_MAX_PAGES` failure). This module caps
# the target linux-lts at the newest version archzfs ships a prebuilt
# zfs-linux-lts for, fetching that exact version from archive.archlinux.org when
# the mirror has moved past it.
#
# This is the target-kernel analogue of the archzfs-Compatible ISO ceiling
# (ADR 0023, lib/packages/iso-resolver.sh) — but resolved from `zfs-linux-lts-*`
# assets (the 6.x lts series), NOT `zfs-linux-*` (the default kernel).
#
# Requires: lib/common.sh already sourced (info/warn). curl, jq, pacman,
# repo-add. Degrades to a no-op — never aborts the install — when the lookup is
# unreachable; the ZFS Module Guard (lib/zfs/verify.sh) stays the backstop.
#
# Provides:
#   archzfs_lts_pkgver          newest archzfs-supported linux-lts pkgver
#   archzfs_pick_lts_version    pure pin decision (supported, mirror → pin?)
#   archzfs_resolve_lts_pin     the pacstrap specs to pin, or nothing (no-op)
#   archzfs_lts_pin_prepare     host-side pre-pacstrap setup (warn + local repo)
# =============================================================================

# Guard against double-sourcing.
[[ -n "${_ARCHZFS_KERNEL_SH_SOURCED:-}" ]] && return 0
_ARCHZFS_KERNEL_SH_SOURCED=1

# shellcheck source=./archive.sh
declare -F pkg_fetch_from_archive >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/archive.sh"

# archzfs experimental release — the source of truth for the prebuilt kernels.
ARCHZFS_LTS_API=\
"https://api.github.com/repos/archzfs/archzfs/releases/tags/experimental"

# ── Test seams (override in bats after sourcing) ─────────────────────────────

# Emit archzfs release asset names, one per line.
_archzfs_fetch_lts_assets() {
  curl -fsSL "$ARCHZFS_LTS_API" 2>/dev/null | jq -r '.assets[]?.name'
}

# The current mirror's linux-lts package version (e.g. 6.19.3-1). Requires the
# core db synced (it is, by the time install_base runs pacstrap).
_mirror_lts_pkgver() {
  pacman -Si linux-lts 2>/dev/null | awk '/^Version/{print $3; exit}'
}

# ── Ceiling lookup ───────────────────────────────────────────────────────────

# Newest linux-lts pkgver archzfs ships a prebuilt zfs-linux-lts for, e.g.
# 6.18.52-1. Asset names look like:
#   zfs-linux-lts-2.4.4_6.18.52.1-1-x86_64.pkg.tar.zst
# The `_<...>-<zfsrel>-<arch>` segment is the linux-lts pkgver with its pkgrel
# dash flattened to a dot (6.18.52.1); the last dot is restored to a dash to
# recover the real pkgver (6.18.52-1). Honors ARCHZFS_LTS_CEILING_OVERRIDE — a
# forced-skew seam: set it to a full pkgver to simulate archzfs lagging. Empty
# output on lookup failure (caller degrades).
archzfs_lts_pkgver() {
  if [[ -n "${ARCHZFS_LTS_CEILING_OVERRIDE:-}" ]]; then
    printf '%s\n' "$ARCHZFS_LTS_CEILING_OVERRIDE"
    return 0
  fi
  local dotted
  dotted="$(_archzfs_fetch_lts_assets |
    sed -nE \
      's/^zfs-linux-lts-[0-9.]+_(.+)-[0-9]+-x86_64\.pkg\.tar\.zst$/\1/p' |
    sort -uV | tail -1)"
  [[ -n "$dotted" ]] || return 0
  printf '%s\n' "${dotted%.*}-${dotted##*.}"
}

# ── Pin decision (pure) ──────────────────────────────────────────────────────

# archzfs_pick_lts_version <supported_pkgver> <mirror_pkgver>
# Print <supported_pkgver> when the mirror's linux-lts MINOR is newer than what
# archzfs supports — a minor jump is what breaks the DKMS build. Print nothing
# when the mirror is at or below the supported minor: same-minor patch drift is
# API-compatible, so no pin (stay as fresh as possible), matching the ISO
# resolver's proven rule. Numeric comparison so 6.9 < 6.18.
archzfs_pick_lts_version() {
  local supported="$1" mirror="$2"
  local sM sm mM mm
  IFS='.' read -r sM sm _ <<<"${supported%%-*}"
  IFS='.' read -r mM mm _ <<<"${mirror%%-*}"
  if (( 10#${mM:-0} < 10#${sM:-0} )) \
     || { (( 10#${mM:-0} == 10#${sM:-0} )) && (( 10#${mm:-0} <= 10#${sm:-0} )); }
  then
    return 0
  fi
  printf '%s\n' "$supported"
}

# ── Orchestration ────────────────────────────────────────────────────────────

# Print "linux-lts=<v> linux-lts-headers=<v>" when the target's linux-lts must
# be held back to the archzfs LTS ceiling; print nothing (no-op / degrade) when
# the lookup fails or no pin is needed. Never fails the caller.
archzfs_resolve_lts_pin() {
  local supported mirror pin
  supported="$(archzfs_lts_pkgver)"; [[ -n "$supported" ]] || return 0
  mirror="$(_mirror_lts_pkgver)";    [[ -n "$mirror" ]]    || return 0
  pin="$(archzfs_pick_lts_version "$supported" "$mirror")"
  [[ -n "$pin" ]] || return 0
  printf 'linux-lts=%s linux-lts-headers=%s\n' "$pin" "$pin"
}

# ── Host-side pin setup (before pacstrap) ────────────────────────────────────

# Download linux-lts + linux-lts-headers at <ver> from the archive into
# <repo_dir>, build a pacman db, and register a local unsigned repo in the host
# pacman.conf (pacstrap reads it). The version-pinned specs (=<ver>) then
# resolve from this repo even though the mirror has moved on. Non-zero if any
# step fails.
_archzfs_lts_pin_build_repo() {
  local ver="$1" repo_dir="$2" pkg
  mkdir -p "$repo_dir" || return 1
  for pkg in linux-lts linux-lts-headers; do
    pkg_fetch_from_archive "$pkg" "$ver" \
      "${repo_dir}/${pkg}-${ver}-x86_64.pkg.tar.zst" || return 1
  done
  repo-add "${repo_dir}/archzfs-lts-pin.db.tar.zst" \
    "${repo_dir}"/*.pkg.tar.zst >/dev/null 2>&1 || return 1
  if ! grep -q '^\[archzfs-lts-pin\]' /etc/pacman.conf; then
    cat >>/etc/pacman.conf <<EOF

# archzfs LTS ceiling pin (ADR 0137) — the exact linux-lts the mirror no longer
# carries, so the version-pinned pacstrap spec resolves. Local, unsigned.
[archzfs-lts-pin]
SigLevel = Never
Server = file://${repo_dir}
EOF
  fi
  pacman -Sy --noconfirm >/dev/null 2>&1 || return 1
}

# Run host-side before pacstrap. When a pin resolves: warn (held-back kernel
# visibility), stage the pinned kernel into a local repo, and export
# LTS_PIN_SPECS so collect_packages emits the version-pinned specs. Silent
# no-op when no pin is needed (happy path byte-identical). Never aborts: a
# staging failure degrades to an unpinned install with the ZFS Module Guard as
# the backstop.
archzfs_lts_pin_prepare() {
  local specs; specs="$(archzfs_resolve_lts_pin)"
  [[ -n "$specs" ]] || return 0

  local ver="${specs#linux-lts=}"; ver="${ver%% *}"
  local mirror; mirror="$(_mirror_lts_pkgver)"
  warn "archzfs LTS ceiling: holding linux-lts back" \
       "${mirror:+from ${mirror} }to ${ver}"
  warn "  archzfs has no zfs-dkms build for the newer kernel yet (ADR 0137)."

  if ! _archzfs_lts_pin_build_repo "$ver" \
        "${LTS_PIN_REPO_DIR:-/var/cache/archzfs-lts-pin}"; then
    warn "archzfs LTS ceiling: could not stage the pinned kernel — proceeding"
    warn "  unpinned; the ZFS Module Guard remains the backstop."
    return 0
  fi
  export LTS_PIN_SPECS="$specs"
  info "archzfs LTS ceiling: target linux-lts pinned to ${ver}."
}
