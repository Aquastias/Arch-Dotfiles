#!/usr/bin/env bash
# =============================================================================
# lib/config/store.sh — Config Store (the effectful edge over Config State)
# =============================================================================
# Owns the Guided Installer's triad session files behind a small named
# interface, so no caller pokes the tmpfs paths directly:
#   GUIDED_STATE_FILE     the Config State (a sparse override map — see state.sh)
#   GUIDED_NAV_FILE       the current screen / nav position
#   GUIDED_BASELINE_FILE  the computed baseline the override map layers over
#
# state.sh stays PURE (JSON in/out); this is where the file IPC lives, once. fzf
# runs each keystroke bind in a fresh shell, so the session state must be
# process-external — the backing is a tmpfs file read via the GUIDED_*_FILE path
# the launcher (guided_run_persistent) exports. There is ONE adapter (the file);
# tests set the same globals to a temp path, so behaviour is asserted through it
# unchanged.
#
# Public API:
#   cfgstore_state              → current Config State JSON (stdout)
#   cfgstore_write_state <json> → replace the Config State
#   cfgstore_nav                → current nav JSON
#   cfgstore_write_nav   <json> → replace nav
#   cfgstore_baseline           → the computed baseline JSON ('{}' when unset)
#   cfgstore_write_baseline <j> → seed the baseline (once, at session init)
# =============================================================================

[[ -n "${_STORE_SH_SOURCED:-}" ]] && return 0
_STORE_SH_SOURCED=1

cfgstore_state()       { printf '%s' "$(<"$GUIDED_STATE_FILE")"; }
cfgstore_write_state() { printf '%s\n' "$1" >"$GUIDED_STATE_FILE"; }
cfgstore_nav()         { printf '%s' "$(<"$GUIDED_NAV_FILE")"; }
cfgstore_write_nav()   { printf '%s\n' "$1" >"$GUIDED_NAV_FILE"; }

# The baseline is optional — unset before the launcher computes it, so read
# defensively and fall back to an empty map.
cfgstore_baseline() {
  if [[ -n "${GUIDED_BASELINE_FILE:-}" && -f "${GUIDED_BASELINE_FILE}" ]]; then
    printf '%s' "$(<"$GUIDED_BASELINE_FILE")"
  else
    printf '%s' '{}'
  fi
}
cfgstore_write_baseline() { printf '%s\n' "$1" >"$GUIDED_BASELINE_FILE"; }
