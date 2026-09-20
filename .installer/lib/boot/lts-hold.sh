#!/usr/bin/env bash
# =============================================================================
# lib/boot/lts-hold.sh — ongoing archzfs LTS ceiling hold (ADR 0139)
# =============================================================================
# The runtime counterpart to the install-time pin (ADR 0137). A systemd timer
# runs this on the installed system. When the mirror's newest linux-lts has
# outrun what archzfs can build ZFS against, it sets a marked
#   IgnorePkg = linux-lts linux-lts-headers
# line in /etc/pacman.conf, so `pacman -Syu` upgrades everything else but HOLDS
# the kernel at its installed version — no linux-lts left without a zfs.ko on the
# running system. When archzfs catches up the marked line is removed and the
# kernel upgrades normally. Non-blocking by construction: it only toggles
# pacman's own IgnorePkg; it never aborts a transaction.
#
# Reuses the ceiling logic (archzfs_lts_pkgver / archzfs_pick_lts_version) from
# archzfs-kernel.sh, staged alongside this script at /usr/local/lib/archzfs/.
# Fail-safe: if the archzfs ceiling or the newest available version can't be
# determined (e.g. offline), it leaves the current hold state untouched.
# =============================================================================

# The comment that marks OUR IgnorePkg line, so we never touch an operator's.
_LTS_HOLD_MARK='# archzfs-lts-hold'

# Pure I/O: set (want=1) or clear (want=0) the marked IgnorePkg line in the
# [options] block of <conf>. Idempotent — any existing marked line is removed
# first, so repeated calls converge. Never touches unmarked IgnorePkg lines.
lts_hold_set() {
  local conf="$1" want="$2"
  [[ -f "$conf" ]] || return 0
  sed -i "\|${_LTS_HOLD_MARK}\$|d" "$conf"
  if [[ "$want" == 1 ]]; then
    sed -i "/^\[options\]/a IgnorePkg = linux-lts linux-lts-headers  ${_LTS_HOLD_MARK}" \
      "$conf"
  fi
}

# The newest linux-lts version the mirrors currently offer, from a throwaway
# db sync that never touches the system's pacman db (checkupdates-style). Empty
# on failure (offline / lookup error).
_lts_hold_newest_available() {
  local tmp; tmp="$(mktemp -d)" || return 1
  # pacman drops to its download user for fetches, which then can't write into a
  # root-owned 0700 tempdir. Mirror checkupdates(8): symlink the real local db
  # and make the tree writable by the download user.
  mkdir -p "$tmp/sync"
  ln -s /var/lib/pacman/local "$tmp/local" 2>/dev/null
  chmod -R a+rwX "$tmp"
  local ver=""
  if pacman -Sy --dbpath "$tmp" --logfile /dev/null >/dev/null 2>&1; then
    ver="$(pacman -Si --dbpath "$tmp" linux-lts 2>/dev/null \
      | awk '/^Version/{print $3; exit}')"
  fi
  rm -rf "$tmp"
  [[ -n "$ver" ]] && printf '%s\n' "$ver"
}

# Lib-only sourcing for tests: skip the runtime below.
[[ "${LTS_HOLD_LIB_ONLY:-0}" == "1" ]] && return 0

# Bring in the shared ceiling logic (defines archzfs_lts_pkgver /
# archzfs_pick_lts_version). Staged next to this script on the target.
_LTS_HOLD_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=../packages/archzfs-kernel.sh
source "${_LTS_HOLD_DIR}/archzfs-kernel.sh"

_lts_hold_run() {
  local conf="${LTS_HOLD_CONF:-/etc/pacman.conf}"

  local ceiling; ceiling="$(archzfs_lts_pkgver)"
  [[ -n "$ceiling" ]] || { echo "archzfs-lts-hold: no archzfs ceiling — leaving hold state unchanged." >&2; return 0; }

  local newest; newest="$(_lts_hold_newest_available)"
  [[ -n "$newest" ]] || { echo "archzfs-lts-hold: could not read newest linux-lts — leaving hold state unchanged." >&2; return 0; }

  # archzfs_pick_lts_version prints the ceiling version when <newest> outruns it
  # at the minor level (⇒ hold), nothing when newest is within the ceiling.
  if [[ -n "$(archzfs_pick_lts_version "$ceiling" "$newest")" ]]; then
    lts_hold_set "$conf" 1
    echo "archzfs-lts-hold: holding linux-lts — mirror ${newest} outruns archzfs ceiling ${ceiling}."
  else
    lts_hold_set "$conf" 0
    echo "archzfs-lts-hold: linux-lts ${newest} within archzfs ceiling ${ceiling} — no hold."
  fi
}

_lts_hold_run
