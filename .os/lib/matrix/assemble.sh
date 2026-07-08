#!/usr/bin/env bash
# =============================================================================
# lib/matrix/assemble.sh — Combination Matrix Cell → Effective Config adapter
# =============================================================================
# Maps a matrix cell's axis assignment onto a Guided Config State and runs the
# existing Guided assembler to a device-baked Effective Config — the exact
# artifact a menu-driven install produces, so one assembler feeds both tiers
# (ADR 0046). Tier 1 validates this config on the host; Tier 2 installs it in a
# VM via the config seam.
#
# Thin: it seeds the menu-derived launch defaults (cfgstate_seed_defaults), lays
# the cell's axes over them as overrides, and delegates disk baking to
# emit_effective. Pure: JSON in/out, no TTY, no disk writes. Requires OS_DIR.
#
# Public API:
#   matrix_cell_state    <cell>  → the Config State for the cell
#   matrix_cell_assemble <cell>  → the device-baked Effective Config
# =============================================================================

# shellcheck source=../config/state.sh
[[ "$(type -t cfgstate_new)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../config/state.sh"
# shellcheck source=../config/seed.sh
[[ "$(type -t cfgstate_seed_defaults)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../config/seed.sh"
# shellcheck source=../config/emit.sh
[[ "$(type -t emit_effective)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../config/emit.sh"

# _matrix_mode_for_topology <topology> — the install mode a topology installs
# under: `single` for the single-disk topology, `multi` for every multi-disk
# one (mirror/raidz*/raid0/raid1/raid10/stripe). Mirrors the guided controller's
# topology→mode split.
_matrix_mode_for_topology() {
  case "$1" in
  single) printf 'single\n' ;;
  *)      printf 'multi\n' ;;
  esac
}

# matrix_cell_state <cell> — the Config State the assembler consumes: the
# menu-derived launch defaults with the cell's axes laid over as overrides.
matrix_cell_state() {
  local cell="$1" fs enc mode state desktop
  fs="$(jq -r '.axes.filesystem' <<<"$cell")"
  enc="$(jq -r '.axes.encryption' <<<"$cell")"
  # mode: the cell's own mode (generator cells carry it) else derived from
  # topology (the slice-01 tracer cell shape).
  mode="$(jq -r '.axes.mode // empty' <<<"$cell")"
  [[ -n "$mode" ]] || mode="$(_matrix_mode_for_topology \
    "$(jq -r '.axes.topology' <<<"$cell")")"

  state="$(cfgstate_seed_defaults "$(cfgstate_new)")"
  state="$(cfgstate_set "$state" filesystem "$(jq -n --arg f "$fs" '$f')")"
  state="$(cfgstate_set "$state" mode "$(jq -n --arg m "$mode" '$m')")"
  state="$(cfgstate_set "$state" options.encryption "$enc")"

  # desktop: only when the cell carries the axis. A Tier-2 scalar ("kde"/"none")
  # maps onto the config's desktop array ([] for "none"); a Tier-1 storage cell
  # has no desktop axis, so the seeded default stands untouched.
  desktop="$(jq -c '.axes.desktop // empty' <<<"$cell")"
  if [[ -n "$desktop" ]]; then
    state="$(cfgstate_set "$state" environment.desktop \
      "$(jq -c 'if type=="array" then .
                elif . == "none" then []
                else [.] end' <<<"$desktop")")"
  fi
  printf '%s\n' "$state"
}

# matrix_cell_assemble <cell> — the device-baked Effective Config for the cell.
# Single-disk cells bake onto /dev/sda; multi-disk topology assignment lands in
# a later slice.
matrix_cell_assemble() {
  local cell="$1" state
  state="$(matrix_cell_state "$cell")"
  # Single-disk baking (the emit/run path exercises single cells); the multi-disk
  # and data-pool disk assignment is the profile synthesizer's job (slice 05).
  emit_effective "$state" '{"mode":"single","disk":"/dev/sda"}'
}
