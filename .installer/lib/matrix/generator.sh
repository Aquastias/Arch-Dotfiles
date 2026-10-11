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
  jq -r '
    .filesystem as $fs | .topology as $topo
    | (if .encryption then "enc" else "plain" end) as $enc
    | (if .impermanence then "-imp" else "" end) as $imp
    | (if .data_pool == null then ""
       else "-pool-" + .data_pool.filesystem
            + (if .data_pool.encryption then "-penc" else "" end) end) as $pool
    | "\($fs)-\($topo)-\($enc)\($imp)\($pool)"
  ' <<<"$1"
}

# ── data-pool options (per-group fs × encryption, incl. mixed-fs) ────────────

# _generator_data_pool_specs — every optional data-pool spec, one JSON per line:
# the empty pool (null) plus each built filesystem × {plaintext, encrypted}. A
# single-disk pool (disk_count 1, topology single) keeps the cross-product
# tractable while still exercising mixed-fs and per-group encryption.
_generator_data_pool_specs() {
  printf 'null\n'
  local pool_filesystem pool_encryption topology
  for pool_filesystem in $(_generator_root_filesystems); do
    topology="$(_generator_single_topology "$pool_filesystem")"
    for pool_encryption in false true; do
      jq -c -n --arg fs "$pool_filesystem" --argjson enc "$pool_encryption" \
        --arg topo "$topology" \
        '{filesystem:$fs, encryption:$enc, topology:$topo, disk_count:1}'
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
  local axes id
  for encryption in false true; do
    for impermanence in $(_generator_impermanence_values "$filesystem"); do
      while IFS= read -r pool; do
        axes="$(jq -c -n \
          --arg fs "$filesystem" --arg mode "$mode" --arg topo "$topology" \
          --argjson enc "$encryption" --argjson imp "$impermanence" \
          --argjson pool "$pool" \
          --argjson dc "$(_generator_topology_disk_count "$topology")" '{
            filesystem:$fs, mode:$mode, topology:$topo, disk_count:$dc,
            encryption:$enc, impermanence:$imp, data_pool:$pool
          }')"
        id="$(_generator_tier1_slug "$axes")"
        jq -c -n --arg id "$id" --argjson axes "$axes" \
          '{id:$id, tier:1, axes:$axes}'
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
  local topologies
  topologies="$(printf '%s\n' "${_MATRIX_TIER2_TOPOLOGIES[@]}" \
    | jq -R . | jq -s -c .)"
  local fss; fss="$(_generator_root_filesystems | jq -R . | jq -s -c .)"
  jq -c -n --argjson fs "$fss" --argjson topo "$topologies" '{
    filesystem:   $fs,
    topology:     $topo,
    encryption:   [false, true],
    impermanence: [false, true],
    kernel:       ["lts", "zen"],
    bootloader:   ["systemd-boot", "grub", "efistub", "limine", "refind"],
    desktop:      ["none", "kde", "hyprland"],
    gpu:          ["auto", "amd", "nvidia", "intel"],
    swap:         [true, false]
  }'
}

# _generator_tier2_constraints — the exclusion set, derived from the menu
# functions: a (filesystem, topology) pair is forbidden unless the topology is
# that filesystem's single-disk mode or one of its menu multi topologies;
# ext4/xfs forbid impermanence (no native snapshots).
_generator_tier2_constraints() {
  local filesystem topology allowed cons=()
  for filesystem in $(_generator_root_filesystems); do
    allowed=" single $(_generator_multi_topologies "$filesystem" \
      | awk '{ printf "%s ", $0 }') "
    for topology in "${_MATRIX_TIER2_TOPOLOGIES[@]}"; do
      [[ "$allowed" == *" $topology "* ]] && continue
      cons+=("$(jq -c -n --arg fs "$filesystem" --arg t "$topology" \
        '{filesystem:$fs, topology:$t}')")
    done
    case "$filesystem" in
    ext4 | xfs)
      cons+=("$(jq -c -n --arg fs "$filesystem" \
        '{filesystem:$fs, impermanence:true}')")
      ;;
    esac
  done
  printf '%s\n' "${cons[@]}" | jq -s -c .
}

# _generator_tier2_slug <row_json> — a stable id for a pairwise cell.
_generator_tier2_slug() {
  jq -r '
    "t2-\(.filesystem)-\(.topology)"
    + (if .encryption then "-enc" else "-plain" end)
    + (if .impermanence then "-imp" else "" end)
    + "-k\(.kernel)-b\(.bootloader)-d\(.desktop)-g\(.gpu)"
    + (if .swap then "-swap" else "-noswap" end)
  ' <<<"$1"
}

# _generator_pairwise_row_to_cell <row_json> — a pairwise row → a Tier-2 cell.
# Mode and disk_count derive from the topology; data pools are covered by Tier-1
# + seeds, so a pairwise cell has none.
_generator_pairwise_row_to_cell() {
  local row="$1" topology mode disk_count id
  topology="$(jq -r '.topology' <<<"$row")"
  [[ "$topology" == single ]] && mode=single || mode=multi
  disk_count="$(_generator_topology_disk_count "$topology")"
  id="$(_generator_tier2_slug "$row")"
  jq -c -n --arg id "$id" --arg mode "$mode" --argjson dc "$disk_count" \
    --argjson row "$row" '{
      id:$id, tier:2,
      axes:($row + {mode:$mode, disk_count:$dc, data_pool:null})
    }'
}

# _generator_tier2_seeds — the pinned historical-bug cells, unioned
# unconditionally so a known regression can never silently drop out of the
# Tier-2 set (ADR 0046).
_generator_tier2_seeds() {
  # zfs root + btrfs data pool (mixed-fs, the classic bug-dense case).
  jq -c -n '{id:"seed-zfs-root-btrfs-pool", tier:2, axes:{
    filesystem:"zfs", mode:"single", topology:"single", disk_count:1,
    encryption:false, impermanence:false,
    data_pool:{filesystem:"btrfs", encryption:false, topology:"single",
               disk_count:1}}}'
  # ext4 root + zfs data pool (mixed-fs, the other direction).
  jq -c -n '{id:"seed-ext4-root-zfs-pool", tier:2, axes:{
    filesystem:"ext4", mode:"single", topology:"single", disk_count:1,
    encryption:false, impermanence:false,
    data_pool:{filesystem:"zfs", encryption:false, topology:"none",
               disk_count:1}}}'
  # btrfs raid1 encrypted multi-disk (per-device LUKS under btrfs raid).
  jq -c -n '{id:"seed-btrfs-raid1-enc-multi", tier:2, axes:{
    filesystem:"btrfs", mode:"multi", topology:"raid1", disk_count:2,
    encryption:true, impermanence:false, data_pool:null}}'
  # xfs root (the modprobe-before-root-mount case).
  jq -c -n '{id:"seed-xfs-root", tier:2, axes:{
    filesystem:"xfs", mode:"single", topology:"single", disk_count:1,
    encryption:false, impermanence:false, data_pool:null}}'
  # zfs keyfile-on-root + encrypted pool (root plaintext, pool key on root).
  jq -c -n '{id:"seed-zfs-keyfile-root-enc-pool", tier:2, axes:{
    filesystem:"zfs", mode:"single", topology:"single", disk_count:1,
    encryption:false, impermanence:false,
    data_pool:{filesystem:"zfs", encryption:true, topology:"none",
               disk_count:1}}}'
  # nvidia × kernel: pin the DKMS-against-headers build for each kernel.
  local kernel
  for kernel in lts zen; do
    jq -c -n --arg k "$kernel" '{id:("seed-nvidia-k"+$k), tier:2, axes:{
      filesystem:"zfs", mode:"single", topology:"single", disk_count:1,
      encryption:false, impermanence:false, data_pool:null,
      kernel:$k, bootloader:"systemd-boot", desktop:"kde", gpu:"nvidia",
      swap:true}}'
  done
}

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
  } | jq -c -s 'unique_by(.id) | .[]'
}

# matrix_all_cells [seed] — Tier-1 ∪ Tier-2 (for emit/run cell-id resolution).
matrix_all_cells() {
  { matrix_tier1_cells; matrix_tier2_cells "${1:-0}"; } | jq -c -s 'unique_by(.id) | .[]'
}
