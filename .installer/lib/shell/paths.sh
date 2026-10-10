#!/usr/bin/env bash
# =============================================================================
# lib/shell/paths.sh — path helpers for Program Install Scripts
# =============================================================================
# Readable stand-ins for dirname/basename (ADR 0153 Tool Tiers). Twins live in
# lib/common.sh and lib/chroot/chroot-common.sh — one per world, never shared.
# Used by: shell-stdlib.sh (facade).
# =============================================================================

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
