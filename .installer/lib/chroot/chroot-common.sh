#!/usr/bin/env bash
# =============================================================================
# lib/chroot/chroot-common.sh — helpers shared by chroot-side scripts
# =============================================================================
# lib/common.sh is NOT sourced inside arch-chroot; this is the chroot-side
# analog for the handful of helpers those scripts share.
#
# Staged flat into /root/lib-chroot/ (chroot_configure_system copies the whole
# lib/chroot/ tree), so it is always a direct sibling of its consumers — in the
# source tree AND in the chroot. Consumers source it as
#   source "$_LIB_DIR/chroot-common.sh"   (_LIB_DIR = the script's directory)
# with no ../ fallback (unlike install-state.sh, which lives one level up in the
# source tree).
# =============================================================================

[[ -n "${_CHROOT_COMMON_SH_SOURCED:-}" ]] && return 0
_CHROOT_COMMON_SH_SOURCED=1

# chroot_error_trap <tag>
# Installs an ERR trap that reports the failing line with a [chroot:<tag>]
# prefix. Callers run under `set -Eeuo pipefail`, so the trap fires on any
# unhandled error and -E propagates it into functions. $LINENO is left
# unexpanded here so it resolves to the failing line when the trap fires.
chroot_error_trap() {
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
# bash/sh ship with base and are skipped. Shared by create-user + password.sh.
ensure_login_shell_installed() {
  local shell="$1" bin package
  [[ -x "$shell" ]] && return 0
  bin="$(base_name "$shell")"
  case "$bin" in
    bash|sh) return 0 ;;
    zsh)     package=zsh ;;
    fish)    package=fish ;;
    *)       package="$bin" ;;
  esac
  echo "  [chroot] login shell '${shell}' missing — installing '${package}'" >&2
  pacman -S --noconfirm --needed "$package"
}

# ── Path helpers (ADR 0153) — one copy per world, never shared ──

# parent_directory <path> — the directory holding <path>, like dirname.
parent_directory() {
  local path="$1"
  while [[ "$path" == */ && "$path" != / ]]; do path="${path%/}"; done
  if [[ "$path" != */* ]]; then
    printf '.\n'
    return 0
  fi
  path="${path%/*}"
  while [[ "$path" == */ ]]; do path="${path%/}"; done
  printf '%s\n' "${path:-/}"
}

# base_name <path> [suffix] — the last part of <path>, like basename.
base_name() {
  local path="$1" suffix="${2:-}"
  while [[ "$path" == */ && "$path" != / ]]; do path="${path%/}"; done
  [[ "$path" == / ]] || path="${path##*/}"
  [[ -n "$suffix" && "$path" != "$suffix" ]] && path="${path%"$suffix"}"
  printf '%s\n' "$path"
}
