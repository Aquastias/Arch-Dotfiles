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
#   archzfs_kernel_lts_package_version  newest archzfs-supported linux-lts
#                                       pkgver
#   archzfs_kernel_pick_lts_version     pure pin decision (supported, mirror →
#                                       pin?)
#   archzfs_kernel_resolve_lts_pin      the pacstrap specs to pin, or nothing
#   archzfs_kernel_lts_pin_prepare      host-side pre-pacstrap setup (warn +
#                                       local repo)
#   archzfs_kernel_lts_module_package   zfs-linux-lts (prebuilt) for a pure-lts
#                                       install, or nothing (keep zfs-dkms)
#
# Used by: lib/packages/package-list.sh, lib/boot/lts-hold.sh, and the chroot
# (staged by lib/chroot.sh, installed by lib/chroot/configure.sh).
# =============================================================================

# Guard against double-sourcing.
[[ -n "${_ARCHZFS_KERNEL_SH_SOURCED:-}" ]] && return 0
_ARCHZFS_KERNEL_SH_SOURCED=1

# shellcheck source=./archive.sh
declare -F archive_fetch_package >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/archive.sh"

# archzfs experimental release — the source of truth for the prebuilt kernels.
ARCHZFS_LTS_API=\
"https://api.github.com/repos/archzfs/archzfs/releases/tags/experimental"

# ── Test seams (override in bats after sourcing) ─────────────────────────────

# Emit archzfs release asset names, one per line.
_archzfs_kernel_fetch_lts_assets() {
  curl -fsSL "$ARCHZFS_LTS_API" 2>/dev/null | jq -r '.assets[]?.name'
}

# The current mirror's linux-lts package version (e.g. 6.19.3-1). Requires the
# core db synced (it is, by the time package_list_install_base runs pacstrap).
_archzfs_kernel_mirror_lts_package_version() {
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
archzfs_kernel_lts_package_version() {
  if [[ -n "${ARCHZFS_LTS_CEILING_OVERRIDE:-}" ]]; then
    printf '%s\n' "$ARCHZFS_LTS_CEILING_OVERRIDE"
    return 0
  fi
  local dotted
  dotted="$(_archzfs_kernel_fetch_lts_assets \
    | awk '/^zfs-linux-lts-[0-9.]+_.+-[0-9]+-x86_64\.pkg\.tar\.zst$/ {
        sub(/^zfs-linux-lts-[0-9.]+_/, "")
        sub(/-[0-9]+-x86_64\.pkg\.tar\.zst$/, "")
        print
      }' \
    | sort -uV | awk 'END { print }')"
  [[ -n "$dotted" ]] || return 0
  printf '%s\n' "${dotted%.*}-${dotted##*.}"
}

# Seam: list linux-lts pkgvers available on the Arch Linux Archive, one per
# line. Overridable in tests.
_archzfs_kernel_fetch_archive_lts_versions() {
  curl -fsSL "https://archive.archlinux.org/packages/l/linux-lts/" 2>/dev/null |
    grep -oE 'linux-lts-[0-9][^"<> ]*-x86_64\.pkg\.tar\.zst' |
    awk '{ sub(/^linux-lts-/, ""); sub(/-x86_64\.pkg\.tar\.zst$/, "")
          print }' |
    sort -uV
}

# _archzfs_kernel_minor_at_or_below <version> <ceiling> — rc 0 when
# <version>'s major.minor is at or below <ceiling>'s. Numeric, so 6.9 < 6.18.
_archzfs_kernel_minor_at_or_below() {
  local version_major version_minor ceiling_major ceiling_minor
  IFS='.' read -r version_major version_minor _ <<<"${1%%-*}"
  IFS='.' read -r ceiling_major ceiling_minor _ <<<"${2%%-*}"
  (( 10#${version_major:-0} < 10#${ceiling_major:-0} )) && return 0
  (( 10#${version_major:-0} == 10#${ceiling_major:-0} )) \
    && (( 10#${version_minor:-0} <= 10#${ceiling_minor:-0} ))
}

# Pin-version candidates, NEWEST-first: linux-lts versions available on the
# archive whose major.minor is at or below the archzfs ceiling <ceiling_pkgver>.
# The archzfs-built version is normally the top one; older compatible versions
# follow as fallbacks when the exact version can't be fetched (ADR 0139 amends
# ADR 0137). Pure given the seam.
archzfs_kernel_pin_candidates() {
  local ceiling="$1" version
  # newest-first (sort -V ascending → reverse)
  while IFS= read -r version; do
    [[ -n "$version" ]] || continue
    _archzfs_kernel_minor_at_or_below "$version" "$ceiling" \
      && printf '%s\n' "$version"
  done < <(_archzfs_kernel_fetch_archive_lts_versions | sort -rV)
  return 0
}

# ── Pin decision (pure) ──────────────────────────────────────────────────────

# archzfs_kernel_pick_lts_version <supported_pkgver> <mirror_pkgver>
# Print <supported_pkgver> when the mirror's linux-lts is newer than it at all
# (minor, patch or pkgrel): the prebuilt zfs-linux-lts depends on its exact
# linux-lts, so even a patch bump must be held back (ADR 0137 amendment;
# 6.18.56 → 6.18.57 broke pacstrap, VM-observed). Nothing when the mirror is
# at or below it.
archzfs_kernel_pick_lts_version() {
  local supported="$1" mirror="$2"
  _archzfs_kernel_version_newer "$mirror" "$supported" || return 0
  printf '%s\n' "$supported"
}

# _archzfs_kernel_version_newer <a> <b> — rc 0 when pkgver <a> is newer than
# <b>: numeric per field over major.minor.patch, then pkgrel (6.18.9 < 6.18.52).
_archzfs_kernel_version_newer() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    count_a = split(a, left, /[.-]/); count_b = split(b, right, /[.-]/)
    count = count_a > count_b ? count_a : count_b
    for (i = 1; i <= count; i++) {
      if (left[i] + 0 > right[i] + 0) exit 0
      if (left[i] + 0 < right[i] + 0) exit 1
    }
    exit 1
  }'
}

# ── Orchestration ────────────────────────────────────────────────────────────

# Print "linux-lts=<v> linux-lts-headers=<v>" when the target's linux-lts must
# be held back to the archzfs LTS ceiling; print nothing (no-op / degrade) when
# the lookup fails or no pin is needed. Never fails the caller.
archzfs_kernel_resolve_lts_pin() {
  local supported mirror pin
  supported="$(archzfs_kernel_lts_package_version)"
  [[ -n "$supported" ]] || return 0
  mirror="$(_archzfs_kernel_mirror_lts_package_version)"
  [[ -n "$mirror" ]] || return 0
  pin="$(archzfs_kernel_pick_lts_version "$supported" "$mirror")"
  [[ -n "$pin" ]] || return 0
  printf 'linux-lts=%s linux-lts-headers=%s\n' "$pin" "$pin"
}

# archzfs_kernel_lts_module_package <kernel_token…>
# The ZFS module package for the root pool. Default is zfs-dkms (builds against
# any kernel), but archzfs's zfs-dkms SOURCE lags the kernel even at the ceiling
# — its prebuilt zfs-linux-lts is patched for the new kernel, the dkms source is
# not (the `BIO_MAX_PAGES` break, VM-verified). So for a pure-lts install where
# archzfs ships a prebuilt, use that prebuilt: it carries a working module for
# the (ceiling-pinned) linux-lts and needs no DKMS compile. Echo "zfs-linux-lts"
# then; nothing otherwise (mixed kernels keep the single-zfs-dkms path).
archzfs_kernel_lts_module_package() {
  local -a kernels=("$@")
  [[ ${#kernels[@]} -eq 1 && "${kernels[0]}" == "lts" ]] || return 0
  # Read the ceiling published by archzfs_kernel_lts_pin_prepare (which runs
  # first), so list-building makes no network call. Empty ⇒ no prebuilt ⇒ keep
  # zfs-dkms.
  [[ -n "${ARCHZFS_LTS_SUPPORTED:-}" ]] || return 0
  printf '%s\n' "zfs-linux-lts"
}

# ── Host-side pin setup (before pacstrap) ────────────────────────────────────

# Stage the pinned linux-lts + headers from the archive into a local pacman
# repo in <repository-directory> and register it (unsigned) in the host
# pacman.conf, so pacstrap resolves the version-pinned specs even though the
# mirror has moved on. Tries <requested> first, then the closest-available-
# compatible archive versions (ADR 0139), so a vanished exact version doesn't
# force a degrade. Prints the CHOSEN version on stdout; non-zero if no
# candidate could be fetched or any step fails.
_archzfs_kernel_lts_pin_build_repository() {
  local requested="$1" repository_directory="$2"
  mkdir -p "$repository_directory" || return 1
  local chosen
  chosen="$(_archzfs_kernel_lts_pin_fetch_first "$requested" \
    "$repository_directory")" || return 1

  repo-add "${repository_directory}/archzfs-lts-pin.db.tar.zst" \
    "${repository_directory}/linux-lts-${chosen}-x86_64.pkg.tar.zst" \
    "${repository_directory}/linux-lts-headers-${chosen}-x86_64.pkg.tar.zst" \
    >/dev/null 2>&1 || return 1
  local pacman_config_file="${PACMAN_CONF:-/etc/pacman.conf}"
  if ! grep -q '^\[archzfs-lts-pin\]' "$pacman_config_file"; then
    cat >>"$pacman_config_file" <<EOF

# archzfs LTS ceiling pin (ADR 0137) — the exact linux-lts the mirror no longer
# carries, so the version-pinned pacstrap spec resolves. Local, unsigned.
[archzfs-lts-pin]
SigLevel = Never
Server = file://${repository_directory}
EOF
  fi
  pacman -Sy --noconfirm >/dev/null 2>&1 || return 1
  printf '%s\n' "$chosen"
}

# _archzfs_kernel_lts_pin_fetch_first <requested> <repository-directory> —
# download linux-lts + headers for the first candidate (requested, then the
# deduped fallbacks) the archive serves; print it, rc 1 when none.
_archzfs_kernel_lts_pin_fetch_first() {
  local requested="$1" repository_directory="$2"
  local -a candidates=("$requested")
  local fallback
  while IFS= read -r fallback; do
    [[ -n "$fallback" && "$fallback" != "$requested" ]] \
      && candidates+=("$fallback")
  done < <(archzfs_kernel_pin_candidates "$requested")

  local candidate kernel_file headers_file
  for candidate in "${candidates[@]}"; do
    kernel_file="${repository_directory}/linux-lts-${candidate}"
    kernel_file+="-x86_64.pkg.tar.zst"
    headers_file="${repository_directory}/linux-lts-headers-${candidate}"
    headers_file+="-x86_64.pkg.tar.zst"
    # 1>&2: archive_fetch_package logs via info() → stdout; this function's
    # stdout IS the chosen version (captured by the caller), so route the
    # fetch's stdout to stderr or it corrupts LTS_PIN_SPECS (the pin would emit
    # malformed pacstrap targets). Keep the logs visible on stderr; drop only
    # curl's noise.
    if archive_fetch_package linux-lts "$candidate" "$kernel_file" \
         1>&2 2>/dev/null \
       && archive_fetch_package linux-lts-headers "$candidate" \
         "$headers_file" 1>&2 2>/dev/null
    then
      printf '%s\n' "$candidate"
      return 0
    fi
    rm -f "$kernel_file" "$headers_file"
  done
  return 1
}

# Run host-side before pacstrap. When a pin resolves: warn (held-back kernel
# visibility), stage the pinned kernel into a local repo, and export
# LTS_PIN_SPECS so package_list_collect emits the version-pinned specs. Silent
# no-op when no pin is needed (happy path byte-identical). Never aborts: a
# staging failure degrades to an unpinned install with the ZFS Module Guard as
# the backstop.
archzfs_kernel_lts_pin_prepare() {
  # Publish the archzfs-supported lts ceiling for package_list_collect's module
  # swap (archzfs_kernel_lts_module_package) — the one place the network lookup
  # happens, so list-building stays offline. Empty when archzfs ships no lts
  # prebuilt.
  ARCHZFS_LTS_SUPPORTED="$(archzfs_kernel_lts_package_version)"
  export ARCHZFS_LTS_SUPPORTED

  local specs; specs="$(archzfs_kernel_resolve_lts_pin)"
  [[ -n "$specs" ]] || return 0

  local version="${specs#linux-lts=}"; version="${version%% *}"
  local mirror; mirror="$(_archzfs_kernel_mirror_lts_package_version)"
  warn "archzfs LTS ceiling: holding linux-lts back" \
       "${mirror:+from ${mirror} }to ${version} (or closest available)."
  warn "  archzfs has no zfs-dkms build for the newer kernel yet (ADR 0137)."

  # The repository build may fall back to the closest available compatible
  # version; use whatever it actually staged for the pacstrap spec.
  local chosen
  chosen="$(_archzfs_kernel_lts_pin_build_repository "$version" \
    "${LTS_PIN_REPO_DIR:-/var/cache/archzfs-lts-pin}")" || chosen=""
  if [[ -z "$chosen" ]]; then
    warn "archzfs LTS ceiling: could not stage the pinned kernel — proceeding"
    warn "  unpinned; the ZFS Module Guard remains the backstop."
    return 0
  fi
  export LTS_PIN_SPECS="linux-lts=${chosen} linux-lts-headers=${chosen}"
  info "archzfs LTS ceiling: target linux-lts pinned to ${chosen}."
}

# Remove the temporary [archzfs-lts-pin] local repo block from <conf>. The pin
# repo is only needed for the pacstrap transaction; left in place it leaks into
# the installed system (pacstrap copies pacman.conf into the target, and
# chroot.sh re-copies it) and then breaks `pacman -Sy`/`-Fy` — the local repo
# directory does not exist in the target. Idempotent; no-op when absent.
# Call on the HOST conf after pacstrap (so the chroot copy is clean) and on the
# target conf defensively (ADR 0137).
archzfs_kernel_lts_pin_cleanup() {
  local pacman_config_file="${1:-/etc/pacman.conf}"
  [[ -f "$pacman_config_file" ]] || return 0
  grep -q '^\[archzfs-lts-pin\]' "$pacman_config_file" || return 0
  # Delete our comment header through the Server line (the whole appended
  # block).
  sed -i '/^# archzfs LTS ceiling pin (ADR 0137)/,\#^Server = file://.*archzfs-lts-pin#d' \
    "$pacman_config_file"
  # Belt-and-suspenders: drop a bare header/directives if the comment drifted.
  sed -i '/^\[archzfs-lts-pin\]/,/^Server = /d' "$pacman_config_file"
}
