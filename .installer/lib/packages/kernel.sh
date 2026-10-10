#!/usr/bin/env bash
# =============================================================================
# lib/packages/kernel.sh — Kernel Selection token table (single source of truth)
# =============================================================================
# Maps Kernel Selection flavour tokens to their kernel package + headers. The
# one table here drives package install (host-side,
# lib/packages/package-list.sh), the initramfs preset, and the bootloader
# default entry (chroot-side). Staged into the chroot alongside install-state.sh
# so both sides share one mapping. Adding a flavour is a one-line change. See
# ADR 0024.
#
# Used by: 03-install.sh, lib/config/install-config.sh,
# lib/packages/package-list.sh, lib/packages/package-resolver.sh; chroot:
# lib/chroot/bootloader-common.sh, lib/chroot/initcpio.sh.
# =============================================================================

[[ -n "${_KERNEL_SH_SOURCED:-}" ]] && return 0
_KERNEL_SH_SOURCED=1

# Fallback error when common.sh isn't sourced (e.g. inside arch-chroot, where
# the chroot consumers source only install-state.sh + this file).
if ! declare -F error >/dev/null 2>&1; then
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
  local spec token
  for spec in "${_KERNEL_TOKEN_MAP[@]}"; do
    IFS='|' read -r token _ <<< "$spec"
    printf '%s ' "$token"
  done
}

# True iff <token> is a known flavour.
kernel_is_valid_token() {
  local want="$1" spec token
  for spec in "${_KERNEL_TOKEN_MAP[@]}"; do
    IFS='|' read -r token _ <<< "$spec"
    [[ "$token" == "$want" ]] && return 0
  done
  return 1
}

# kernel_package <token> → kernel package base (e.g. lts → linux-lts).
kernel_package() {
  local want="$1" spec token base
  for spec in "${_KERNEL_TOKEN_MAP[@]}"; do
    IFS='|' read -r token base <<< "$spec"
    [[ "$token" == "$want" ]] && { printf '%s\n' "$base"; return 0; }
  done
  error "Unknown kernel token: '$want' (valid: $(kernel_valid_tokens))."
}

# kernel_headers_package <token> → matching headers package
# (e.g. linux-lts-headers).
kernel_headers_package() {
  printf '%s-headers\n' "$(kernel_package "$1")"
}

# kernel_bases_primary_first <primary-token> <token…> — the package bases to
# boot, Primary Kernel first (the default entry, ADR 0038), then the rest of
# the Kernel Selection in order, each once. Loaders rendering per-kernel
# entries (limine, grub) iterate this.
kernel_bases_primary_first() {
  local primary token kernel_base
  primary="$(kernel_package "$1")"; shift
  printf '%s\n' "$primary"
  for token in "$@"; do
    kernel_base="$(kernel_package "$token")"
    [[ "$kernel_base" == "$primary" ]] || printf '%s\n' "$kernel_base"
  done | awk '!seen[$0]++'
}
