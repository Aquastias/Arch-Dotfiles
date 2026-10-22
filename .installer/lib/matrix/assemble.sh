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
  local mode; mode="$(jq -r '.axes.mode // empty' <<<"$1")"
  [[ -n "$mode" ]] && { printf '%s\n' "$mode"; return 0; }
  _assemble_mode_for_topology "$(jq -r '.axes.topology' <<<"$1")"
}

# _assemble_disk_devices <count> — /dev/sda, /dev/sdb, … as a JSON array.
_assemble_disk_devices() {
  local i letters="abcdefghijklmnopqrstuvwxyz" out=()
  for ((i = 0; i < $1; i++)); do out+=("/dev/sd${letters:i:1}"); done
  printf '%s\n' "${out[@]}" | jq -R . | jq -s -c .
}

# matrix_cell_state <cell> — the Config State the assembler consumes: the
# menu-derived launch defaults with the cell's axes laid over as overrides.
matrix_cell_state() {
  local cell="$1" filesystem encryption mode impermanence state desktop \
    topology dcroot
  filesystem="$(jq -r '.axes.filesystem' <<<"$cell")"
  encryption="$(jq -r '.axes.encryption' <<<"$cell")"
  impermanence="$(jq -r '.axes.impermanence // false' <<<"$cell")"
  mode="$(_assemble_cell_mode "$cell")"

  state="$(config_state_seed_defaults "$(config_state_new)")"
  state="$(config_state_set "$state" filesystem "$(jq -n --arg f \
    "$filesystem" '$f')")"
  state="$(config_state_set "$state" mode "$(jq -n --arg m "$mode" '$m')")"
  state="$(config_state_set "$state" options.encryption "$encryption")"
  # impermanence rides the enabled bool; the dataset (rpool/persist) and mount
  # (/persist) default through the accessors, so a zfs root validates as-is.
  state="$(config_state_set "$state" options.impermanence.enabled \
    "$impermanence")"

  # multi mode needs the os_pool skeleton (topology + root disk count) so the
  # picker can bake the picked devices onto it.
  if [[ "$mode" == multi ]]; then
    topology="$(jq -r '.axes.topology' <<<"$cell")"
    dcroot="$(jq -r '.axes.disk_count // 2' <<<"$cell")"
    state="$(config_state_set "$state" os_pool "$(jq -c -n \
      --arg t "$topology" --argjson dc "$dcroot" \
      '{pool_name:"rpool", topology:$t, disk_count:$dc}')")"
  fi

  # desktop: only when the cell carries the axis. A Tier-2 scalar ("kde"/"none")
  # maps onto the config's desktop array ([] for "none"); a Tier-1 storage cell
  # has no desktop axis, so the seeded default stands untouched.
  desktop="$(jq -c '.axes.desktop // empty' <<<"$cell")"
  if [[ -n "$desktop" ]]; then
    state="$(config_state_set "$state" environment.desktop \
      "$(jq -c 'if type=="array" then .
                elif . == "none" then []
                else [.] end' <<<"$desktop")")"
  fi
  state="$(_assemble_scalar_axes "$cell" "$state")"
  printf '%s\n' "$state"
}

# _assemble_scalar_axes <cell> <state> — lay the Tier-2 scalar axes a cell
# carries over the state (a Tier-1 cell has none, so defaults stand). Missing
# these once made every cell install lts + systemd-boot + gpu auto (20261022).
_assemble_scalar_axes() {
  local cell="$1" state="$2" axis path value
  while IFS='|' read -r axis path; do
    value="$(jq -c --arg a "$axis" \
      'if (.axes | has($a)) then .axes[$a] else empty end' <<<"$cell")"
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
    disk_count="$(jq -r '.axes.disk_count // 2' <<<"$cell")"
    assignment="$(jq -c -n \
      --argjson d "$(_assemble_disk_devices "$disk_count")" \
      '{mode:"multi", os_pool:$d}')"
  else
    assignment='{"mode":"single","disk":"/dev/sda"}'
  fi
  emit_effective "$state" "$assignment"
}
