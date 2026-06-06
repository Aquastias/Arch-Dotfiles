#!/usr/bin/env bash
# =============================================================================
# lib/packages/kernel.sh — Kernel Selection token table (single source of truth)
# =============================================================================
# Maps Kernel Selection flavour tokens to their kernel package + headers. The
# one table here drives package install (host-side, lib/packages/list.sh), the
# initramfs preset, and the bootloader default entry (chroot-side). Staged into
# the chroot alongside install-state.sh so both sides share one mapping.
# Adding a flavour is a one-line change. See ADR 0024.
# =============================================================================

[[ -n "${_KERNEL_SH_SOURCED:-}" ]] && return 0
_KERNEL_SH_SOURCED=1

# Fallback error when common.sh isn't sourced (e.g. inside arch-chroot, where
# the chroot consumers source only install-state.sh + this file).
if [[ "$(type -t error)" != "function" ]]; then
  error() { echo "[kernel] $*" >&2; exit 1; }
fi

# token → kernel package base. Headers are "<base>-headers".
_KERNEL_TOKEN_MAP=(
  "lts|linux-lts"
  "default|linux"
  "zen|linux-zen"
  "hardened|linux-hardened"
)

# Space-separated list of valid tokens — for error messages.
kernel_valid_tokens() {
  local spec t
  for spec in "${_KERNEL_TOKEN_MAP[@]}"; do
    IFS='|' read -r t _ <<< "$spec"
    printf '%s ' "$t"
  done
}

# True iff <token> is a known flavour.
kernel_is_valid_token() {
  local want="$1" spec t
  for spec in "${_KERNEL_TOKEN_MAP[@]}"; do
    IFS='|' read -r t _ <<< "$spec"
    [[ "$t" == "$want" ]] && return 0
  done
  return 1
}

# kernel_pkg <token> → kernel package base (e.g. lts → linux-lts).
kernel_pkg() {
  local want="$1" spec t b
  for spec in "${_KERNEL_TOKEN_MAP[@]}"; do
    IFS='|' read -r t b <<< "$spec"
    [[ "$t" == "$want" ]] && { printf '%s\n' "$b"; return 0; }
  done
  error "Unknown kernel token: '$want' (valid: $(kernel_valid_tokens))."
}

# kernel_headers_pkg <token> → matching headers package (e.g. linux-lts-headers).
kernel_headers_pkg() {
  printf '%s-headers\n' "$(kernel_pkg "$1")"
}
