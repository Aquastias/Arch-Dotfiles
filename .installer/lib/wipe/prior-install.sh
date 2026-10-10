#!/usr/bin/env bash
# =============================================================================
# lib/wipe/prior-install.sh — clear a failed install's /mnt scratch state
# =============================================================================
# A failed 03-install.sh leaves ZFS pools imported (altroot=/mnt) and datasets +
# ESP mounted under /mnt; wipe_detect_disks then sees a mounted partition and
# SKIPS the disk you want to wipe. So clear that scratch state first. Scoped to
# /mnt and pools with altroot=/mnt (never the live system); unmount/export is
# non-destructive — no data erased, pools re-importable.
#
# Used by: 02-wipe.sh (runs before disk detection). Requires lib/common.sh.
# main()-free, so sourcing is inert.
# =============================================================================

# Injectable seams (overridden in tests).
_prior_install_mounts_under_mount_root() {
  findmnt -rno TARGET 2>/dev/null | grep -E '^/mnt(/|$)' || true
}
_prior_install_pools_with_mount_root_altroot() {
  command_exists zpool || return 0
  zpool list -H -o name,altroot 2>/dev/null \
    | awk '$2 ~ /^\/mnt(\/|$)/ {print $1}'
}

# Returns 0 if a previous-install scratch state is present at /mnt.
wipe_prior_install_present() {
  [[ -n "$(_prior_install_mounts_under_mount_root)" ]] && return 0
  [[ -n "$(_prior_install_pools_with_mount_root_altroot)" ]] && return 0
  return 1
}

wipe_reset_prior_install() {
  wipe_prior_install_present || return 0

  section "Previous Install Environment Detected"
  _prior_install_report
  _prior_install_confirm_teardown || return 0
  _prior_install_teardown

  if wipe_prior_install_present; then
    warn "Some /mnt state remains — inspect: mount | grep /mnt ; zpool list"
  else
    info "Previous install env cleared — disk is now wipeable."
  fi
}

_prior_install_report() {
  local mounts pools line
  mounts="$(_prior_install_mounts_under_mount_root)"
  pools="$(_prior_install_pools_with_mount_root_altroot | join_words || true)"
  if [[ -n "$mounts" ]]; then
    warn "Mounted under /mnt:"
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "      ${line}"
    done <<<"$mounts"
  fi
  [[ -n "$pools" ]] && warn "Imported pool(s) with altroot=/mnt: ${pools}"
  return 0
}

# Returns 1 when the operator keeps the state (unattended always tears down).
_prior_install_confirm_teardown() {
  [[ "${INSTALL_UNATTENDED:-0}" == "1" ]] && return 0
  echo ""
  local reply
  local question="  Tear down this /mnt install env so the disk is wipeable?"
  read -rp "$question [y/N]: " reply
  case "$reply" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) warn "Left /mnt state intact — the target disk will stay excluded."
       return 1 ;;
  esac
}

_prior_install_teardown() {
  # 1. swapoff any swap backed by a zvol (e.g. /dev/zvol/rpool/swap).
  if command_exists swapon; then
    local swap_device
    while IFS= read -r swap_device; do
      [[ -n "$swap_device" ]] && { swapoff "$swap_device" 2>/dev/null || true; }
    done < <(swapon --show=NAME --noheadings 2>/dev/null \
             | grep '^/dev/zvol/' || true)
  fi
  # 2. Unmount the whole /mnt tree (ESP + datasets); lazy fallback for busy.
  umount -R /mnt 2>/dev/null || umount -Rl /mnt 2>/dev/null || true
  # 3. Export the /mnt-scoped pools (forced fallback) to release the disk.
  local pool
  while IFS= read -r pool; do
    [[ -z "$pool" ]] && continue
    warn "Exporting pool '${pool}'"
    zpool export "$pool" 2>/dev/null \
      || zpool export -f "$pool" 2>/dev/null || true
  done < <(_prior_install_pools_with_mount_root_altroot)
}
