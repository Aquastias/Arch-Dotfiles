#!/usr/bin/env bash
# =============================================================================
# lib/chroot/chroot-common.sh — helpers shared by chroot-side scripts
# =============================================================================
# lib/common.sh is NOT sourced inside arch-chroot; this is the chroot-side
# analog for the handful of helpers those scripts share.
#
# Staged flat into /root/lib-chroot/ (configure_system copies the whole
# lib/chroot/ tree), so it is always a direct sibling of its consumers — in the
# source tree AND in the chroot. Consumers source it as
#   source "$(dirname "${BASH_SOURCE[0]}")/chroot-common.sh"
# with no ../ fallback (unlike install-state.sh, which lives one level up in the
# source tree).
# =============================================================================

[[ -n "${_CHROOT_COMMON_SH_SOURCED:-}" ]] && return 0
_CHROOT_COMMON_SH_SOURCED=1

# chroot_err_trap <tag>
# Installs an ERR trap that reports the failing line with a [chroot:<tag>]
# prefix. Callers run under `set -Eeuo pipefail`, so the trap fires on any
# unhandled error and -E propagates it into functions. $LINENO is left
# unexpanded here so it resolves to the failing line when the trap fires.
chroot_err_trap() {
  local tag="$1"
  # SC2064: ${tag} is meant to expand now; \$LINENO is escaped so it resolves
  # to the failing line when the trap fires.
  # shellcheck disable=SC2064
  trap "echo \"[chroot:${tag}] failed at line \$LINENO\" >&2" ERR
}

# ensure_login_shell_installed <shell>
# A login shell whose binary is absent is unusable: display managers exec
# `$SHELL --login` and bounce back to the greeter before the session ever runs
# (SDDM's wayland-session wrapper does exactly this). The guided menu offers
# zsh/fish for users AND root (ADR 0054), but neither is guaranteed by a
# profile's package list — so install the chosen shell's package here.
# bash/sh ship with base and are skipped. Shared by create-user.sh + password.sh.
ensure_login_shell_installed() {
  local shell="$1" bin pkg
  [[ -x "$shell" ]] && return 0
  bin="$(basename "$shell")"
  case "$bin" in
    bash|sh) return 0 ;;
    zsh)     pkg=zsh ;;
    fish)    pkg=fish ;;
    *)       pkg="$bin" ;;
  esac
  echo "  [chroot] login shell '${shell}' missing — installing '${pkg}'" >&2
  pacman -S --noconfirm --needed "$pkg"
}
