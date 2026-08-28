#!/usr/bin/env bash
# =============================================================================
# lib/packages/audio.sh — Audio package set (pure, single source of truth)
# =============================================================================
# The PipeWire stack installed whenever any desktop is selected. Pure: shared by
# the install path (config/environment.sh's _resolve_env_audio) and the Package
# Resolver (resolver.sh's audio source), so the two cannot drift. The DECISION
# to install audio (a desktop is present) stays with each caller; this is only
# the name list.
# =============================================================================

[[ -n "${_AUDIO_SH_SOURCED:-}" ]] && return 0
_AUDIO_SH_SOURCED=1

# audio_packages — the PipeWire stack, one package per line.
audio_packages() {
  printf '%s\n' \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    gst-plugin-pipewire pipewire-jack libpulse
}
