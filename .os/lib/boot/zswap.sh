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
# default. compressor/max_pool_percent fall back to the kernel-sane defaults
# when absent (a string / a number — neither is swallowed by `//`).
zswap_cmdline_params() {
  jq -r '
    (.swap == true) as $swap
    | (.zswap.enabled == true) as $on
    | if ($swap and $on) then
        "zswap.enabled=1"
        + " zswap.compressor=\(.zswap.compressor // "zstd")"
        + " zswap.max_pool_percent=\(.zswap.max_pool_percent // 20)"
      else "" end' <<<"$1"
}
