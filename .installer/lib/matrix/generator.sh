#!/usr/bin/env bash
# =============================================================================
# lib/matrix/generator.sh — Combination Matrix Cell Generator + Constraint Model
# =============================================================================
# The real generator (ADR 0046). It derives its axes and exclusions from the
# menu's OWN option functions (_controller_built_root_filesystems, _controller_topologies_for_filesystem)
# — never a hand-kept spec — so the matrix can't drift from what the menu offers
# and can't emit a cell the menu can't produce. It classifies axes through the
# Axis Registry and draws the Tier-2 cover through the pure Pairwise Reducer.
#
# Two cell sets (JSON lines, cell-id + axis assignment):
#   matrix_tier1_cells         exhaustive storage-cluster cross-product under
#                              the exclusions — root fs × topology × encryption
#                              × impermanence × a per-group data pool (fs/enc),
#                              including mixed-filesystem and per-group-encryption
#                              cells. No VM cost — regenerated live in bats.
#   matrix_tier2_cells [seed]  a pairwise (2-wise) cover over the install-
#                              affecting axes ∪ the pinned historical-bug seeds.
#   matrix_all_cells  [seed]   tier1 ∪ tier2 (cell-id resolution for emit/run).
#
# Pure: JSON on stdout, no TTY, no disk writes. Requires INSTALLER_DIR (for the
# menu
# functions' lockstep with the layout dispatch).
#
# Public API: matrix_tier1_cells / matrix_tier2_cells / matrix_all_cells
#
# Used by: lib/matrix/cells.sh, lib/matrix/driver.sh, lib/matrix/profile.sh,
# lib/matrix/records.sh.
# =============================================================================

# menu option functions (the source of truth for reachability).
# shellcheck source=../guided/controller.sh
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

declare -F _controller_topologies_for_filesystem >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../guided/controller.sh"
# shellcheck source=./pairwise.sh
declare -F matrix_pairwise >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/pairwise.sh"

# ── derived axes (from the menu functions) ───────────────────────────────────

# _generator_root_filesystems — the built root filesystems (menu-derived).
_generator_root_filesystems() { _controller_built_root_filesystems; }

# _generator_multi_topologies <fs> — the multi-disk topologies the menu offers
# for <fs> (its topology cycle minus the single-disk entry). Empty ⇒ <fs> has no
# multi-disk story, so it is single-only (ext4/xfs).
_generator_multi_topologies() {
  _controller_topologies_for_filesystem "$1" | grep -vx single || true
}

# _generator_impermanence_values <fs> — the impermanence values reachable for
# <fs>. Impermanence needs native snapshots, so only zfs/btrfs offer `true` (ADR
# 0040/ 0044); ext4/xfs are false-only.
_generator_impermanence_values() {
  case "$1" in zfs | btrfs) printf '%s\n' false true ;; *) printf 'false\n' ;; esac
}

# _generator_single_topology <fs> — the topology a single-disk group of <fs>
# uses. zfs names a single-vdev pool `none` (a raw disk, no redundancy vdev);
# every other filesystem calls it `single`. Matches
# _validation_topology_for_filesystem's valid sets (zfs has no `single`;
# btrfs/ext4/xfs have no `none`).
_generator_single_topology() {
  case "$1" in zfs) printf 'none\n' ;; *) printf 'single\n' ;; esac
}

# _generator_topology_disk_count <topology> — the canonical (minimum valid) disk
# count for a topology; feeds the profile synthesizer's Σ disk_count (slice 05).
_generator_topology_disk_count() {
  case "$1" in
  single | none) echo 1 ;;
  mirror | stripe | raid0 | raid1) echo 2 ;;
  raidz1) echo 3 ;;
  raidz2 | raid10) echo 4 ;;
  *) echo 1 ;;
  esac
}

# ── cell id ──────────────────────────────────────────────────────────────────

# _generator_tier1_slug <axes_json> — a stable, readable cell-id from a Tier-1
# cell's storage axes. zfs/single/plain/no-pool ⇒ "zfs-single-plain".
_generator_tier1_slug() {
  printf '%s\n' "$1" | jq -r -f "${BASH_SOURCE[0]%/*}/generator-tier1-slug.jq"
}

# _generator_json_array <text>… — the arguments as a compact JSON array of
# strings, in order.
_generator_json_array() {
  local json='[]' text
  for text in "$@"; do
    # The array so far, with this string added at the end.
    json="$(jq -c -n --argjson array "$json" --arg text "$text" \
      '$array + [$text]')"
  done
  printf '%s\n' "$json"
}

# ── data-pool options (per-group fs × encryption, incl. mixed-fs) ────────────

# _generator_data_pool_specs — every optional data-pool spec, one JSON per line:
# the empty pool (null) plus each built filesystem × {plaintext, encrypted}. A
# single-disk pool (disk_count 1, topology single) keeps the cross-product
# tractable while still exercising mixed-fs and per-group encryption.
_GENERATOR_POOL='{filesystem: $fs, encryption: $enc, topology: $topo,'
_GENERATOR_POOL+=' disk_count: 1}'

_generator_data_pool_specs() {
  printf 'null\n'
  local pool_filesystem pool_encryption topology
  for pool_filesystem in $(_generator_root_filesystems); do
    topology="$(_generator_single_topology "$pool_filesystem")"
    for pool_encryption in false true; do
      # A single-disk pool of that filesystem and encryption.
      jq -c -n --arg fs "$pool_filesystem" --argjson enc "$pool_encryption" \
        --arg topo "$topology" "$_GENERATOR_POOL"
    done
  done
}

# ── Tier-1: exhaustive storage cluster ───────────────────────────────────────

matrix_tier1_cells() {
  local filesystem mode topology
  local -a topologies
  for filesystem in $(_generator_root_filesystems); do
    for mode in single multi; do
      topologies=()
      if [[ "$mode" == single ]]; then
        topologies=(single)
      else
        mapfile -t topologies < <(_generator_multi_topologies "$filesystem")
      fi
      for topology in ${topologies[@]+"${topologies[@]}"}; do
        _generator_tier1_topology_cells "$filesystem" "$mode" "$topology"
      done
    done
  done
}

# _generator_tier1_topology_cells <filesystem> <mode> <topology> — every
# encryption × impermanence × data-pool cell for one root topology.
_generator_tier1_topology_cells() {
  local filesystem="$1" mode="$2" topology="$3" encryption impermanence pool
  local axes id root disk_count
  local axes_of='{filesystem: $fs, mode: $mode, topology: $topo,'
  axes_of+=' disk_count: $dc, encryption: $enc, impermanence: $imp,'
  axes_of+=' data_pool: $pool}'
  disk_count="$(_generator_topology_disk_count "$topology")"
  # The root as the menu sees it: filesystem and mode.
  root="$(jq -c -n --arg fs "$filesystem" --arg mode "$mode" \
    '{filesystem: $fs, mode: $mode}')"
  for encryption in false true; do
    # the menu locks encryption off on some roots (btrfs raid): never emitted
    [[ "$encryption" == true ]] && menu_state_encryption_locked "$root" \
      && continue
    for impermanence in $(_generator_impermanence_values "$filesystem"); do
      while IFS= read -r pool; do
        # The cell's storage axes.
        axes="$(jq -c -n \
          --arg fs "$filesystem" --arg mode "$mode" --arg topo "$topology" \
          --argjson enc "$encryption" --argjson imp "$impermanence" \
          --argjson pool "$pool" --argjson dc "$disk_count" "$axes_of")"
        id="$(_generator_tier1_slug "$axes")"
        # The Tier-1 cell.
        jq -c -n --arg id "$id" --argjson axes "$axes" \
          '{id: $id, tier: 1, axes: $axes}'
      done < <(_generator_data_pool_specs)
    done
  done
  return 0
}

# ── Tier-2: pairwise cover over install-affecting axes ∪ pinned seeds ─────────

# The full root-topology value set the pairwise axis draws from. "single" is the
# single-disk mode for any filesystem; the multi topologies are the union of
# every filesystem's menu topologies. Per-filesystem reachability is enforced by
# the exclusion constraints, not by pruning this list.
_MATRIX_TIER2_TOPOLOGIES=(single mirror raidz1 raidz2 stripe raid0 raid1 raid10)

# _generator_tier2_axes — the install-affecting pairwise axes as an axes JSON.
_generator_tier2_axes() {
  local topologies filesystems
  local -a root_filesystems
  mapfile -t root_filesystems < <(_generator_root_filesystems)
  topologies="$(_generator_json_array "${_MATRIX_TIER2_TOPOLOGIES[@]}")"
  filesystems="$(_generator_json_array "${root_filesystems[@]}")"
  jq -c -n --argjson fs "$filesystems" --argjson topo "$topologies" \
    -f "${BASH_SOURCE[0]%/*}/generator-tier2-axes.jq"
}

# _generator_tier2_constraints — the exclusion set, derived from the menu
# functions: a (filesystem, topology) pair is forbidden unless the topology is
# that filesystem's single-disk mode or one of its menu multi topologies;
# ext4/xfs forbid impermanence (no native snapshots); a multi topology whose
# root the menu locks encryption off on (menu_state_encryption_locked) forbids
# encryption.
_generator_tier2_constraints() {
  local filesystem topology allowed cons=()
  for filesystem in $(_generator_root_filesystems); do
    # Its topologies, space-padded: single plus the menu's multi ones.
    allowed=" single $(_generator_multi_topologies "$filesystem" \
      | paste -sd' ' -) "
    for topology in "${_MATRIX_TIER2_TOPOLOGIES[@]}"; do
      [[ "$allowed" == *" $topology "* ]] && continue
      # A forbidden filesystem + topology pair.
      cons+=("$(jq -c -n --arg fs "$filesystem" --arg t "$topology" \
        '{filesystem: $fs, topology: $t}')")
    done
    local multi_root
    # The filesystem as a multi-disk root.
    multi_root="$(jq -c -n --arg fs "$filesystem" \
      '{filesystem: $fs, mode: "multi"}')"
    for topology in "${_MATRIX_TIER2_TOPOLOGIES[@]}"; do
      [[ "$allowed" == *" $topology "* && "$topology" != single ]] || continue
      menu_state_encryption_locked "$multi_root" || continue
      # A forbidden encrypted multi-disk root.
      cons+=("$(jq -c -n --arg fs "$filesystem" --arg t "$topology" \
        '{filesystem: $fs, topology: $t, encryption: true}')")
    done
    case "$filesystem" in
    ext4 | xfs)
      # No impermanence without native snapshots.
      cons+=("$(jq -c -n --arg fs "$filesystem" \
        '{filesystem: $fs, impermanence: true}')")
      ;;
    esac
  done
  # The constraints as one array.
  printf '%s\n' "${cons[@]}" | jq -s -c .
}

# _generator_tier2_slug <row_json> — a stable id for a pairwise cell.
_generator_tier2_slug() {
  printf '%s\n' "$1" | jq -r -f "${BASH_SOURCE[0]%/*}/generator-tier2-slug.jq"
}

# _generator_pairwise_row_to_cell <row_json> — a pairwise row → a Tier-2 cell.
# Mode and disk_count derive from the topology; data pools are covered by Tier-1
# + seeds, so a pairwise cell has none.
_generator_pairwise_row_to_cell() {
  local row="$1" topology mode disk_count id
  local cell='{id: $id, tier: 2,'
  cell+=' axes: ($row + {mode: $mode, disk_count: $dc, data_pool: null})}'
  # The row's topology.
  topology="$(printf '%s\n' "$row" | jq -r '.topology')"
  [[ "$topology" == single ]] && mode=single || mode=multi
  disk_count="$(_generator_topology_disk_count "$topology")"
  id="$(_generator_tier2_slug "$row")"
  # The Tier-2 cell: the row plus its mode, disk count and no data pool.
  jq -c -n --arg id "$id" --arg mode "$mode" --argjson dc "$disk_count" \
    --argjson row "$row" "$cell"
}

# _generator_tier2_seeds — the pinned historical-bug cells, unioned
# unconditionally so a known regression can never silently drop out of the
# Tier-2 set (ADR 0046).
_generator_tier2_seeds() {
  jq -c -n -f "${BASH_SOURCE[0]%/*}/generator-seeds.jq"
}

# The cells (read as one array) each once, by id, one per line.
_GENERATOR_UNIQUE='unique_by(.id) | .[]'

# matrix_tier2_cells [seed] — the pairwise cover ∪ the pinned seeds. Seeds are
# de-duplicated against the cover by id (a seed that coincides with a drawn row
# is kept once).
matrix_tier2_cells() {
  local seed="${1:-0}" axes cons
  axes="$(_generator_tier2_axes)"
  cons="$(_generator_tier2_constraints)"

  { while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      _generator_pairwise_row_to_cell "$row"
    done < <(matrix_pairwise "$axes" "$cons" "$seed")
    _generator_tier2_seeds
  # Each cell once, by id.
  } | jq -c -s "$_GENERATOR_UNIQUE"
}

# matrix_all_cells [seed] — Tier-1 ∪ Tier-2 (for emit/run cell-id resolution).
matrix_all_cells() {
  # Each cell once, by id.
  { matrix_tier1_cells; matrix_tier2_cells "${1:-0}"; } \
    | jq -c -s "$_GENERATOR_UNIQUE"
}
