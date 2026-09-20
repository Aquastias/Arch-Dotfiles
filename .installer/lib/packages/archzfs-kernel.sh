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
#   archzfs_lts_module_pkg      zfs-linux-lts (prebuilt) for a pure-lts install,
#                               or nothing (keep zfs-dkms)
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

# Seam: list linux-lts pkgvers available on the Arch Linux Archive, one per
# line. Overridable in tests.
_archzfs_fetch_archive_lts_versions() {
  curl -fsSL "https://archive.archlinux.org/packages/l/linux-lts/" 2>/dev/null |
    grep -oE 'linux-lts-[0-9][^"<> ]*-x86_64\.pkg\.tar\.zst' |
    sed -E 's/^linux-lts-(.*)-x86_64\.pkg\.tar\.zst$/\1/' | sort -uV
}

# Pin-version candidates, NEWEST-first: linux-lts versions available on the
# archive whose major.minor is at or below the archzfs ceiling <ceiling_pkgver>.
# The archzfs-built version is normally the top one; older compatible versions
# follow as fallbacks when the exact version can't be fetched (ADR 0139 amends
# ADR 0137). Pure given the seam.
archzfs_pin_candidates() {
  local ceiling="$1"
  local cM cm; IFS='.' read -r cM cm _ <<<"${ceiling%%-*}"
  local v vM vm
  # newest-first (sort -V ascending → reverse)
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    IFS='.' read -r vM vm _ <<<"${v%%-*}"
    if (( 10#${vM:-0} < 10#${cM:-0} )) \
       || { (( 10#${vM:-0} == 10#${cM:-0} )) && (( 10#${vm:-0} <= 10#${cm:-0} )); }
    then
      printf '%s\n' "$v"
    fi
  done < <(_archzfs_fetch_archive_lts_versions | sort -rV)
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

# archzfs_lts_module_pkg <kernel_token…>
# The ZFS module package for the root pool. Default is zfs-dkms (builds against
# any kernel), but archzfs's zfs-dkms SOURCE lags the kernel even at the ceiling
# — its prebuilt zfs-linux-lts is patched for the new kernel, the dkms source is
# not (the `BIO_MAX_PAGES` break, VM-verified). So for a pure-lts install where
# archzfs ships a prebuilt, use that prebuilt: it carries a working module for
# the (ceiling-pinned) linux-lts and needs no DKMS compile. Echo "zfs-linux-lts"
# then; nothing otherwise (mixed kernels keep the single-zfs-dkms path).
archzfs_lts_module_pkg() {
  local -a kernels=("$@")
  [[ ${#kernels[@]} -eq 1 && "${kernels[0]}" == "lts" ]] || return 0
  # Read the ceiling published by archzfs_lts_pin_prepare (which runs first),
  # so list-building makes no network call. Empty ⇒ no prebuilt ⇒ keep zfs-dkms.
  [[ -n "${ARCHZFS_LTS_SUPPORTED:-}" ]] || return 0
  printf '%s\n' "zfs-linux-lts"
}

# ── Host-side pin setup (before pacstrap) ────────────────────────────────────

# Download linux-lts + linux-lts-headers at <ver> from the archive into
# <repo_dir>, build a pacman db, and register a local unsigned repo in the host
# pacman.conf (pacstrap reads it). The version-pinned specs (=<ver>) then
# resolve from this repo even though the mirror has moved on. Non-zero if any
# step fails.
# Stage the pinned linux-lts + headers into a local repo and register it. Tries
# <requested> first, then the closest-available-compatible archive versions
# (ADR 0139), so a vanished exact version doesn't force a degrade. Prints the
# CHOSEN version on stdout; non-zero if no candidate could be fetched.
_archzfs_lts_pin_build_repo() {
  local requested="$1" repo_dir="$2"
  mkdir -p "$repo_dir" || return 1

  # Requested version first, then closest-available-compatible fallbacks (deduped).
  local -a cands=("$requested"); local c
  while IFS= read -r c; do
    [[ -n "$c" && "$c" != "$requested" ]] && cands+=("$c")
  done < <(archzfs_pin_candidates "$requested")

  local candidate chosen="" lk hk
  for candidate in "${cands[@]}"; do
    lk="${repo_dir}/linux-lts-${candidate}-x86_64.pkg.tar.zst"
    hk="${repo_dir}/linux-lts-headers-${candidate}-x86_64.pkg.tar.zst"
    if pkg_fetch_from_archive linux-lts "$candidate" "$lk" 2>/dev/null \
       && pkg_fetch_from_archive linux-lts-headers "$candidate" "$hk" 2>/dev/null
    then
      chosen="$candidate"; break
    fi
    rm -f "$lk" "$hk"
  done
  [[ -n "$chosen" ]] || return 1

  repo-add "${repo_dir}/archzfs-lts-pin.db.tar.zst" \
    "${repo_dir}/linux-lts-${chosen}-x86_64.pkg.tar.zst" \
    "${repo_dir}/linux-lts-headers-${chosen}-x86_64.pkg.tar.zst" \
    >/dev/null 2>&1 || return 1
  local conf="${PACMAN_CONF:-/etc/pacman.conf}"
  if ! grep -q '^\[archzfs-lts-pin\]' "$conf"; then
    cat >>"$conf" <<EOF

# archzfs LTS ceiling pin (ADR 0137) — the exact linux-lts the mirror no longer
# carries, so the version-pinned pacstrap spec resolves. Local, unsigned.
[archzfs-lts-pin]
SigLevel = Never
Server = file://${repo_dir}
EOF
  fi
  pacman -Sy --noconfirm >/dev/null 2>&1 || return 1
  printf '%s\n' "$chosen"
}

# Run host-side before pacstrap. When a pin resolves: warn (held-back kernel
# visibility), stage the pinned kernel into a local repo, and export
# LTS_PIN_SPECS so collect_packages emits the version-pinned specs. Silent
# no-op when no pin is needed (happy path byte-identical). Never aborts: a
# staging failure degrades to an unpinned install with the ZFS Module Guard as
# the backstop.
archzfs_lts_pin_prepare() {
  # Publish the archzfs-supported lts ceiling for collect_packages' module swap
  # (archzfs_lts_module_pkg) — the one place the network lookup happens, so
  # list-building stays offline. Empty when archzfs ships no lts prebuilt.
  export ARCHZFS_LTS_SUPPORTED="$(archzfs_lts_pkgver)"

  local specs; specs="$(archzfs_resolve_lts_pin)"
  [[ -n "$specs" ]] || return 0

  local ver="${specs#linux-lts=}"; ver="${ver%% *}"
  local mirror; mirror="$(_mirror_lts_pkgver)"
  warn "archzfs LTS ceiling: holding linux-lts back" \
       "${mirror:+from ${mirror} }to ${ver} (or closest available)."
  warn "  archzfs has no zfs-dkms build for the newer kernel yet (ADR 0137)."

  # build_repo may fall back to the closest available compatible version; use
  # whatever it actually staged for the pacstrap spec.
  local chosen
  chosen="$(_archzfs_lts_pin_build_repo "$ver" \
    "${LTS_PIN_REPO_DIR:-/var/cache/archzfs-lts-pin}")"
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
archzfs_lts_pin_cleanup() {
  local conf="${1:-/etc/pacman.conf}"
  [[ -f "$conf" ]] || return 0
  grep -q '^\[archzfs-lts-pin\]' "$conf" || return 0
  # Delete our comment header through the Server line (the whole appended block).
  sed -i '/^# archzfs LTS ceiling pin (ADR 0137)/,\#^Server = file://.*archzfs-lts-pin#d' \
    "$conf"
  # Belt-and-suspenders: drop a bare header/directives if the comment drifted.
  sed -i '/^\[archzfs-lts-pin\]/,/^Server = /d' "$conf"
}
