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
# Thin: it seeds the menu-derived launch defaults (config_state_seed_defaults),
# lays the cell's axes over them as overrides, and delegates disk baking to
# emit_effective. Pure: JSON in/out, no TTY, no disk writes. Requires
# INSTALLER_DIR.
#
# Public API:
#   matrix_cell_state    <cell>  → the Config State for the cell
#   matrix_cell_assemble <cell>  → the device-baked Effective Config
#
# Used by: lib/config/config-state.sh, lib/config/emit.sh, lib/matrix/synth.sh.
# =============================================================================

# shellcheck source=../config/config-state.sh
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

declare -F config_state_new >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/config-state.sh"
# shellcheck source=../config/emit.sh
declare -F emit_effective >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/emit.sh"

# _assemble_mode_for_topology <topology> — the install mode a topology installs
# under: `single` for the single-disk topology, `multi` for every multi-disk
# one (mirror/raidz*/raid0/raid1/raid10/stripe). Mirrors the guided controller's
# topology→mode split.
_assemble_mode_for_topology() {
  case "$1" in
  single) printf 'single\n' ;;
  *)      printf 'multi\n' ;;
  esac
}

# matrix_cell_state <cell> — the Config State the assembler consumes: the
# menu-derived launch defaults with the cell's axes laid over as overrides.
# _assemble_cell_mode <cell> — the cell's install mode (its own `mode`, else
# derived from the topology).
_assemble_cell_mode() {
  local mode; mode="$(_assemble_field "$1" '.axes.mode // empty')"
  [[ -n "$mode" ]] && { printf '%s\n' "$mode"; return 0; }
  _assemble_mode_for_topology "$(_assemble_field "$1" '.axes.topology')"
}

# _assemble_field <cell> <filter> — one field of a cell, as text (JSON for a
# list or an object).
_assemble_field() {
  # The filter's value in the cell.
  printf '%s\n' "$1" | jq -r "$2"
}

# _assemble_disk_devices <count> — /dev/sda, /dev/sdb, … as a JSON array.
_assemble_disk_devices() {
  local i letters="abcdefghijklmnopqrstuvwxyz" out=()
  for ((i = 0; i < $1; i++)); do out+=("/dev/sd${letters:i:1}"); done
  json_string_array "${out[@]}"
}

# matrix_cell_state <cell> — the Config State the assembler consumes: the
# menu-derived launch defaults with the cell's axes laid over as overrides.
matrix_cell_state() {
  local cell="$1" filesystem encryption mode impermanence state desktop \
    topology dcroot
  filesystem="$(_assemble_field "$cell" '.axes.filesystem')"
  encryption="$(_assemble_field "$cell" '.axes.encryption')"
  impermanence="$(_assemble_field "$cell" '.axes.impermanence // false')"
  mode="$(_assemble_cell_mode "$cell")"

  state="$(config_state_seed_defaults "$(config_state_new)")"
  # The filesystem and the mode as JSON strings.
  state="$(config_state_set "$state" filesystem \
    "$(jq -n --arg f "$filesystem" '$f')")"
  state="$(config_state_set "$state" mode "$(jq -n --arg m "$mode" '$m')")"
  state="$(config_state_set "$state" options.encryption "$encryption")"
  # impermanence rides the enabled bool; the dataset (rpool/persist) and mount
  # (/persist) default through the accessors, so a zfs root validates as-is.
  state="$(config_state_set "$state" options.impermanence.enabled \
    "$impermanence")"

  # multi mode needs the os_pool skeleton (topology + root disk count) so the
  # picker can bake the picked devices onto it.
  if [[ "$mode" == multi ]]; then
    local os_pool='{pool_name: "rpool", topology: $t, disk_count: $dc}'
    topology="$(_assemble_field "$cell" '.axes.topology')"
    dcroot="$(_assemble_field "$cell" '.axes.disk_count // 2')"
    # The root pool skeleton.
    state="$(config_state_set "$state" os_pool \
      "$(jq -c -n --arg t "$topology" --argjson dc "$dcroot" "$os_pool")")"
  fi

  # desktop: only when the cell carries the axis. A Tier-2 scalar ("kde"/"none")
  # maps onto the config's desktop array ([] for "none"); a Tier-1 storage cell
  # has no desktop axis, so the seeded default stands untouched.
  local as_list='if type == "array" then .'
  as_list+=' elif . == "none" then [] else [.] end'
  # The cell's desktop axis as JSON, empty when it has none.
  desktop="$(printf '%s\n' "$cell" | jq -c '.axes.desktop // empty')"
  if [[ -n "$desktop" ]]; then
    # The desktop as the config's list.
    state="$(config_state_set "$state" environment.desktop \
      "$(printf '%s\n' "$desktop" | jq -c "$as_list")")"
  fi
  state="$(_assemble_scalar_axes "$cell" "$state")"
  printf '%s\n' "$state"
}

# _assemble_scalar_axes <cell> <state> — lay the Tier-2 scalar axes a cell
# carries over the state (a Tier-1 cell has none, so defaults stand). Missing
# these once made every cell install lts + systemd-boot + gpu auto (20261022).
_assemble_scalar_axes() {
  local cell="$1" state="$2" axis path value
  local axis_value='if (.axes | has($a)) then .axes[$a] else empty end'
  while IFS='|' read -r axis path; do
    # The axis's value as JSON, empty when the cell lacks it.
    value="$(printf '%s\n' "$cell" | jq -c --arg a "$axis" "$axis_value")"
    [[ -n "$value" ]] || continue
    # the kernel axis is one kernel; the config holds a list
    [[ "$axis" == kernel ]] && value="[$value]"
    state="$(config_state_set "$state" "$path" "$value")"
  done <<'AXES'
kernel|options.kernel
bootloader|options.bootloader
gpu|environment.gpu
swap|options.swap
AXES
  printf '%s\n' "$state"
}

# matrix_cell_assemble <cell> — the device-baked Effective Config for the cell.
# single bakes onto /dev/sda; multi bakes the root os_pool onto /dev/sd{a..} (Σ
# disk_count for the root topology). Data-pool disks are provisioned by the
# synthesizer but not yet baked into the pool — a mixed-fs cell installs its root
# and leaves the extra disk unused (data-pool baking is a follow-on).
matrix_cell_assemble() {
  local cell="$1" state mode disk_count assignment
  state="$(matrix_cell_state "$cell")"
  mode="$(_assemble_cell_mode "$cell")"
  if [[ "$mode" == multi ]]; then
    disk_count="$(_assemble_field "$cell" '.axes.disk_count // 2')"
    # The root pool on the first disk_count disks.
    assignment="$(jq -c -n \
      --argjson d "$(_assemble_disk_devices "$disk_count")" \
      '{mode: "multi", os_pool: $d}')"
  else
    assignment='{"mode":"single","disk":"/dev/sda"}'
  fi
  emit_effective "$state" "$assignment"
}
