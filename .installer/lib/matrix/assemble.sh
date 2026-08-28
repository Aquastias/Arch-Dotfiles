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
# emit_effective. Pure: JSON in/out, no TTY, no disk writes. Requires
# INSTALLER_DIR.
#
# Public API:
#   matrix_cell_state    <cell>  → the Config State for the cell
#   matrix_cell_assemble <cell>  → the device-baked Effective Config
# =============================================================================

# shellcheck source=../config/state.sh
declare -F cfgstate_new >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/state.sh"
# shellcheck source=../config/seed.sh
declare -F cfgstate_seed_defaults >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/seed.sh"
# shellcheck source=../config/emit.sh
declare -F emit_effective >/dev/null 2>&1 \
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
# _matrix_cell_mode <cell> — the cell's install mode (its own `mode`, else
# derived from the topology).
_matrix_cell_mode() {
  local m; m="$(jq -r '.axes.mode // empty' <<<"$1")"
  [[ -n "$m" ]] && { printf '%s\n' "$m"; return 0; }
  _matrix_mode_for_topology "$(jq -r '.axes.topology' <<<"$1")"
}

# _matrix_disk_devices <count> — /dev/sda, /dev/sdb, … as a JSON array.
_matrix_disk_devices() {
  local i letters="abcdefghijklmnopqrstuvwxyz" out=()
  for ((i = 0; i < $1; i++)); do out+=("/dev/sd${letters:i:1}"); done
  printf '%s\n' "${out[@]}" | jq -R . | jq -s -c .
}

# matrix_cell_state <cell> — the Config State the assembler consumes: the
# menu-derived launch defaults with the cell's axes laid over as overrides.
matrix_cell_state() {
  local cell="$1" fs enc mode imp state desktop topo dcroot
  fs="$(jq -r '.axes.filesystem' <<<"$cell")"
  enc="$(jq -r '.axes.encryption' <<<"$cell")"
  imp="$(jq -r '.axes.impermanence // false' <<<"$cell")"
  mode="$(_matrix_cell_mode "$cell")"

  state="$(cfgstate_seed_defaults "$(cfgstate_new)")"
  state="$(cfgstate_set "$state" filesystem "$(jq -n --arg f "$fs" '$f')")"
  state="$(cfgstate_set "$state" mode "$(jq -n --arg m "$mode" '$m')")"
  state="$(cfgstate_set "$state" options.encryption "$enc")"
  # impermanence rides the enabled bool; the dataset (rpool/persist) and mount
  # (/persist) default through the accessors, so a zfs root validates as-is.
  state="$(cfgstate_set "$state" options.impermanence.enabled "$imp")"

  # multi mode needs the os_pool skeleton (topology + root disk count) so the
  # picker can bake the picked devices onto it.
  if [[ "$mode" == multi ]]; then
    topo="$(jq -r '.axes.topology' <<<"$cell")"
    dcroot="$(jq -r '.axes.disk_count // 2' <<<"$cell")"
    state="$(cfgstate_set "$state" os_pool "$(jq -c -n \
      --arg t "$topo" --argjson dc "$dcroot" \
      '{pool_name:"rpool", topology:$t, disk_count:$dc}')")"
  fi

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
# single bakes onto /dev/sda; multi bakes the root os_pool onto /dev/sd{a..} (Σ
# disk_count for the root topology). Data-pool disks are provisioned by the
# synthesizer but not yet baked into the pool — a mixed-fs cell installs its root
# and leaves the extra disk unused (data-pool baking is a follow-on).
matrix_cell_assemble() {
  local cell="$1" state mode n assignment
  state="$(matrix_cell_state "$cell")"
  mode="$(_matrix_cell_mode "$cell")"
  if [[ "$mode" == multi ]]; then
    n="$(jq -r '.axes.disk_count // 2' <<<"$cell")"
    assignment="$(jq -c -n --argjson d "$(_matrix_disk_devices "$n")" \
      '{mode:"multi", os_pool:$d}')"
  else
    assignment='{"mode":"single","disk":"/dev/sda"}'
  fi
  emit_effective "$state" "$assignment"
}
