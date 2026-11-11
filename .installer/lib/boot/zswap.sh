#!/usr/bin/env bash
# =============================================================================
# lib/boot/zswap.sh — zswap kernel command-line fragment (deep, pure)
# =============================================================================
# Maps the Install State (the host↔chroot wire format) to the zswap kernel
# command-line parameters that both Bootloader Adapters append.
#
# zswap is a compressed RAM cache that sits IN FRONT OF the real swap device
# (the ZFS swap zvol / swap partition), so the fragment is emitted ONLY when
# swap is enabled AND zswap is enabled — never a zswap cmdline pointing at a
# swap device that was not created. No `zswap.zpool`: modern kernels hardcode
# zsmalloc and dropped that knob, so emitting it would be a no-op.
#
# Pure: JSON in, a (possibly empty) string out — no TTY, no globals, no
# package. Staged into the chroot lib dir and sourced by the adapters.
#
# Public API:
#   zswap_cmdline_params <install-state-json>  → cmdline fragment (or empty)
# =============================================================================

# zswap_cmdline_params <install-state-json>
# `== true` (not jq `//`) so a stored false is honoured, never read as a
# default. The chroot has no Install Config Reader; install_state_write records
# its zswap defaults, so the zstd / 20 fallback only covers a partial state
# (ADR 0154).
zswap_cmdline_params() {
  local swap enabled compressor percent
  # Whether swap and zswap are on, then zswap's compressor and pool share.
  swap="$(printf '%s\n' "$1" | jq -r '.swap == true')" || return 1
  enabled="$(printf '%s\n' "$1" | jq -r '.zswap.enabled == true')"
  compressor="$(printf '%s\n' "$1" | jq -r '.zswap.compressor // "zstd"')"
  percent="$(printf '%s\n' "$1" | jq -r '.zswap.max_pool_percent // 20')"
  if [[ "$swap" == true && "$enabled" == true ]]; then
    printf 'zswap.enabled=1 zswap.compressor=%s zswap.max_pool_percent=%s\n' \
      "$compressor" "$percent"
  else
    printf '\n'
  fi
}
