#!/usr/bin/env bash
# =============================================================================
# lib/packages/gpu.sh — GPU driver package map (pure, single source of truth)
# =============================================================================
# Maps a RESOLVED GPU vendor to its pacman driver set. Pure: no lspci, no
# network, so both the pure Package Resolver (resolver.sh) and the impure
# environment resolution (config/environment.sh) share one map and cannot drift.
#
# Detection (auto → vendor) and the intel pre-Broadwell refinement stay in the
# install path (config/environment.sh); this map returns the deterministic
# modern default. For intel that is intel-media-driver — the same value the
# resolver reports; the pre-Broadwell libva-intel-driver downgrade is applied
# only install-side, where lspci is available.
# =============================================================================

[[ -n "${_GPU_SH_SOURCED:-}" ]] && return 0
_GPU_SH_SOURCED=1

# gpu_vendor_packages <vendor> → space-separated driver packages (may be empty).
# Vendors: amd | nvidia | intel | vm. `auto` is not a vendor here — it is
# resolved to a concrete vendor before this is called.
gpu_vendor_packages() {
  case "$1" in
    amd)    echo "vulkan-radeon xf86-video-amdgpu mesa" ;;
    nvidia) echo "nvidia-open-dkms nvidia-utils lib32-nvidia-utils" \
                 "libva-nvidia-driver egl-wayland" ;;
    intel)  echo "intel-media-driver" ;;
    vm)     echo "mesa" ;;
  esac
}
