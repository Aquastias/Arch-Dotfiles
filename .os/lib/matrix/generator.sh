#!/usr/bin/env bash
# =============================================================================
# lib/matrix/generator.sh — Combination Matrix Cell Generator + Constraint Model
# =============================================================================
# The real generator (ADR 0046). It derives its axes and exclusions from the
# menu's OWN option functions (_ctl_built_root_filesystems, _ctl_topologies_for_fs)
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
# Pure: JSON on stdout, no TTY, no disk writes. Requires OS_DIR (for the menu
# functions' lockstep with the layout dispatch).
#
# Public API: matrix_tier1_cells / matrix_tier2_cells / matrix_all_cells
# =============================================================================

# menu option functions (the source of truth for reachability).
# shellcheck source=../guided-controller.sh
[[ "$(type -t _ctl_topologies_for_fs)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../guided-controller.sh"
# shellcheck source=./pairwise.sh
[[ "$(type -t matrix_pairwise)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/pairwise.sh"

# ── derived axes (from the menu functions) ───────────────────────────────────

# _matrix_root_filesystems — the built root filesystems (menu-derived).
_matrix_root_filesystems() { _ctl_built_root_filesystems; }

# _matrix_multi_topologies <fs> — the multi-disk topologies the menu offers for
# <fs> (its topology cycle minus the single-disk entry). Empty ⇒ <fs> has no
# multi-disk story, so it is single-only (ext4/xfs).
_matrix_multi_topologies() {
  _ctl_topologies_for_fs "$1" | grep -vx single || true
}

# _matrix_impermanence_values <fs> — the impermanence values reachable for <fs>.
# Impermanence needs native snapshots, so only zfs/btrfs offer `true` (ADR 0040/
# 0044); ext4/xfs are false-only.
_matrix_impermanence_values() {
  case "$1" in zfs | btrfs) printf '%s\n' false true ;; *) printf 'false\n' ;; esac
}

# _matrix_single_topology <fs> — the topology a single-disk group of <fs> uses.
# zfs names a single-vdev pool `none` (a raw disk, no redundancy vdev); every
# other filesystem calls it `single`. Matches _validation_topology_for_fs's
# valid sets (zfs has no `single`; btrfs/ext4/xfs have no `none`).
_matrix_single_topology() {
  case "$1" in zfs) printf 'none\n' ;; *) printf 'single\n' ;; esac
}

# _matrix_topology_disk_count <topology> — the canonical (minimum valid) disk
# count for a topology; feeds the profile synthesizer's Σ disk_count (slice 05).
_matrix_topology_disk_count() {
  case "$1" in
  single | none) echo 1 ;;
  mirror | stripe | raid0 | raid1) echo 2 ;;
  raidz1) echo 3 ;;
  raidz2 | raid10) echo 4 ;;
  *) echo 1 ;;
  esac
}

# ── cell id ──────────────────────────────────────────────────────────────────

# _matrix_tier1_slug <axes_json> — a stable, readable cell-id from a Tier-1
# cell's storage axes. zfs/single/plain/no-pool ⇒ "zfs-single-plain".
_matrix_tier1_slug() {
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

# _matrix_data_pool_specs — every optional data-pool spec, one JSON per line:
# the empty pool (null) plus each built filesystem × {plaintext, encrypted}. A
# single-disk pool (disk_count 1, topology single) keeps the cross-product
# tractable while still exercising mixed-fs and per-group encryption.
_matrix_data_pool_specs() {
  printf 'null\n'
  local pfs penc topo
  for pfs in $(_matrix_root_filesystems); do
    topo="$(_matrix_single_topology "$pfs")"
    for penc in false true; do
      jq -c -n --arg fs "$pfs" --argjson enc "$penc" --arg topo "$topo" \
        '{filesystem:$fs, encryption:$enc, topology:$topo, disk_count:1}'
    done
  done
}

# ── Tier-1: exhaustive storage cluster ───────────────────────────────────────

matrix_tier1_cells() {
  local fs mode topo enc imp pool axes id
  for fs in $(_matrix_root_filesystems); do
    for mode in single multi; do
      local -a topos=()
      if [[ "$mode" == single ]]; then
        topos=(single)
      else
        mapfile -t topos < <(_matrix_multi_topologies "$fs")
      fi
      ((${#topos[@]})) || continue
      for topo in "${topos[@]}"; do
        for enc in false true; do
          for imp in $(_matrix_impermanence_values "$fs"); do
            while IFS= read -r pool; do
              axes="$(jq -c -n \
                --arg fs "$fs" --arg mode "$mode" --arg topo "$topo" \
                --argjson enc "$enc" --argjson imp "$imp" \
                --argjson pool "$pool" \
                --argjson dc "$(_matrix_topology_disk_count "$topo")" '{
                  filesystem:$fs, mode:$mode, topology:$topo, disk_count:$dc,
                  encryption:$enc, impermanence:$imp, data_pool:$pool
                }')"
              id="$(_matrix_tier1_slug "$axes")"
              jq -c -n --arg id "$id" --argjson axes "$axes" \
                '{id:$id, tier:1, axes:$axes}'
            done < <(_matrix_data_pool_specs)
          done
        done
      done
    done
  done
}

# ── Tier-2: pairwise cover over install-affecting axes ∪ pinned seeds ─────────

# The full root-topology value set the pairwise axis draws from. "single" is the
# single-disk mode for any filesystem; the multi topologies are the union of
# every filesystem's menu topologies. Per-filesystem reachability is enforced by
# the exclusion constraints, not by pruning this list.
_MATRIX_TIER2_TOPOLOGIES=(single mirror raidz1 raidz2 stripe raid0 raid1 raid10)

# _matrix_tier2_axes — the install-affecting pairwise axes as an axes JSON.
_matrix_tier2_axes() {
  local topos; topos="$(printf '%s\n' "${_MATRIX_TIER2_TOPOLOGIES[@]}" \
    | jq -R . | jq -s -c .)"
  local fss; fss="$(_matrix_root_filesystems | jq -R . | jq -s -c .)"
  jq -c -n --argjson fs "$fss" --argjson topo "$topos" '{
    filesystem:   $fs,
    topology:     $topo,
    encryption:   [false, true],
    impermanence: [false, true],
    kernel:       ["lts", "zen"],
    bootloader:   ["systemd-boot", "grub"],
    desktop:      ["none", "kde", "hyprland"],
    gpu:          ["auto", "amd", "nvidia", "intel"],
    swap:         [true, false]
  }'
}

# _matrix_tier2_constraints — the exclusion set, derived from the menu functions:
# a (filesystem, topology) pair is forbidden unless the topology is that
# filesystem's single-disk mode or one of its menu multi topologies; ext4/xfs
# forbid impermanence (no native snapshots).
_matrix_tier2_constraints() {
  local fs t allowed cons=()
  for fs in $(_matrix_root_filesystems); do
    allowed=" single $(_matrix_multi_topologies "$fs" | tr '\n' ' ') "
    for t in "${_MATRIX_TIER2_TOPOLOGIES[@]}"; do
      [[ "$allowed" == *" $t "* ]] && continue
      cons+=("$(jq -c -n --arg fs "$fs" --arg t "$t" \
        '{filesystem:$fs, topology:$t}')")
    done
    case "$fs" in
    ext4 | xfs)
      cons+=("$(jq -c -n --arg fs "$fs" '{filesystem:$fs, impermanence:true}')")
      ;;
    esac
  done
  printf '%s\n' "${cons[@]}" | jq -s -c .
}

# _matrix_tier2_slug <row_json> — a stable id for a pairwise cell.
_matrix_tier2_slug() {
  jq -r '
    "t2-\(.filesystem)-\(.topology)"
    + (if .encryption then "-enc" else "-plain" end)
    + (if .impermanence then "-imp" else "" end)
    + "-k\(.kernel)-b\(.bootloader)-d\(.desktop)-g\(.gpu)"
    + (if .swap then "-swap" else "-noswap" end)
  ' <<<"$1"
}

# _matrix_pairwise_row_to_cell <row_json> — a pairwise row → a Tier-2 cell. Mode
# and disk_count derive from the topology; data pools are covered by Tier-1 +
# seeds, so a pairwise cell has none.
_matrix_pairwise_row_to_cell() {
  local row="$1" topo mode dc id
  topo="$(jq -r '.topology' <<<"$row")"
  [[ "$topo" == single ]] && mode=single || mode=multi
  dc="$(_matrix_topology_disk_count "$topo")"
  id="$(_matrix_tier2_slug "$row")"
  jq -c -n --arg id "$id" --arg mode "$mode" --argjson dc "$dc" \
    --argjson row "$row" '{
      id:$id, tier:2,
      axes:($row + {mode:$mode, disk_count:$dc, data_pool:null})
    }'
}

# _matrix_tier2_seeds — the pinned historical-bug cells, unioned unconditionally
# so a known regression can never silently drop out of the Tier-2 set (ADR 0046).
_matrix_tier2_seeds() {
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
  local k
  for k in lts zen; do
    jq -c -n --arg k "$k" '{id:("seed-nvidia-k"+$k), tier:2, axes:{
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
  axes="$(_matrix_tier2_axes)"
  cons="$(_matrix_tier2_constraints)"

  { while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      _matrix_pairwise_row_to_cell "$row"
    done < <(matrix_pairwise "$axes" "$cons" "$seed")
    _matrix_tier2_seeds
  } | jq -c -s 'unique_by(.id) | .[]'
}

# matrix_all_cells [seed] — Tier-1 ∪ Tier-2 (for emit/run cell-id resolution).
matrix_all_cells() {
  { matrix_tier1_cells; matrix_tier2_cells "${1:-0}"; } | jq -c -s 'unique_by(.id) | .[]'
}
