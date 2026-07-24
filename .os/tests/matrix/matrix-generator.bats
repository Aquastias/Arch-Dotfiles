#!/usr/bin/env bats
# Tests for the Cell Generator + Constraint Model (combination-matrix/04, ADR
# 0046). Sourcing the menu's own option functions (_ctl_topologies_for_fs,
# _ctl_built_root_filesystems) + the axis registry + the pairwise reducer, it
# emits two cell sets:
#   Tier-1 = the exhaustive storage-cluster cross-product under the menu's
#            exclusions (incl. mixed-fs + per-group encryption cells).
#   Tier-2 = a pairwise cover over the install-affecting axes ∪ pinned seeds.
# Reachability comes only from the menu functions, so impossible cells are
# structurally excluded. Behaviour under test = the emitted cell SET's
# properties (validity, coverage, seeds, determinism).

setup() {
  OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export OS_DIR
  # the generator + the real validation contract it must not violate.
  # shellcheck source=../../lib/matrix/generator.sh
  source "$OS_DIR/lib/matrix/generator.sh"
  # the REAL topology contract, so the cross-check can't drift from production.
  error() { return 1; }
  # shellcheck source=../../lib/config/validation.sh
  source "$OS_DIR/lib/config/validation.sh"
}

# ── tracer: Tier-1 is a real (non-trivial) set that includes the simplest cell

@test "tier1: emits many cells including the simplest zfs-single-plain" {
  run matrix_tier1_cells
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -gt 1 ]
  # every line is a well-formed cell
  while IFS= read -r c; do
    echo "$c" | jq -e '.id and (.axes | type == "object")'
  done <<<"$output"
  # the tracer cell is present, unchanged in shape
  echo "$output" | jq -e 'select(.id == "zfs-single-plain")
    | .axes.filesystem == "zfs" and .axes.topology == "single"
      and .axes.encryption == false and .axes.impermanence == false'
}

# ── AC1: no cell violates the real topology contract / single-disk rules ────

@test "tier1: every distinct root/pool topology passes _validation_topology_for_fs" {
  local cells; cells="$(matrix_tier1_cells)"

  # ext4/xfs cells are single-disk only (topology single, disk_count 1).
  run bash -c "jq -e 'select(.axes.filesystem==\"ext4\" or .axes.filesystem==\"xfs\")
    | .axes.topology==\"single\" and .axes.disk_count==1' <<<'$cells' | grep -q false"
  [ "$status" -ne 0 ]  # no ext4/xfs cell breaks single-disk

  # every distinct MULTI (fs,topology) passes the real validator.
  local triple fs topo
  while IFS=$'\t' read -r fs topo; do
    run _validation_topology_for_fs os_pool "$fs" "$topo"
    [ "$status" -eq 0 ]
  done < <(jq -r 'select(.axes.mode=="multi")
    | "\(.axes.filesystem)\t\(.axes.topology)"' <<<"$cells" | sort -u)

  # every distinct data-pool (fs,topology) passes the real validator.
  while IFS=$'\t' read -r fs topo; do
    run _validation_topology_for_fs data "$fs" "$topo"
    [ "$status" -eq 0 ]
  done < <(jq -r 'select(.axes.data_pool != null)
    | "\(.axes.data_pool.filesystem)\t\(.axes.data_pool.topology)"' \
    <<<"$cells" | sort -u)
}

# ── AC3: mixed-filesystem and per-group-encryption cells are present ────────

@test "tier1: mixed-fs and per-group-encryption cells exist" {
  local cells; cells="$(matrix_tier1_cells)"
  # zfs root + btrfs data pool (mixed-fs)
  echo "$cells" | jq -e 'select(.axes.filesystem=="zfs"
    and .axes.data_pool.filesystem=="btrfs")' >/dev/null
  # ext4 root + zfs data pool (mixed-fs, the other direction)
  echo "$cells" | jq -e 'select(.axes.filesystem=="ext4"
    and .axes.data_pool.filesystem=="zfs")' >/dev/null
  # root encrypted / pool plaintext AND its inverse (per-group encryption)
  echo "$cells" | jq -e 'select(.axes.encryption==true
    and .axes.data_pool.encryption==false)' >/dev/null
  echo "$cells" | jq -e 'select(.axes.encryption==false
    and .axes.data_pool.encryption==true)' >/dev/null
}

# ── AC4: Tier-1 equals the exhaustive cross-product under exclusions ────────

@test "tier1: cell count equals the exhaustive cross-product; ids unique" {
  local cells; cells="$(matrix_tier1_cells)"

  # recompute the expected size from the menu-derived factors (independently of
  # the nested generator loop).
  local fs roots=0 pools expected=0 multis imps
  pools="$(_matrix_data_pool_specs | wc -l)"
  for fs in $(_matrix_root_filesystems); do
    multis=$(( 1 + $(_matrix_multi_topologies "$fs" | wc -l) ))  # single + multi
    imps=$(_matrix_impermanence_values "$fs" | wc -l)
    roots=$(( roots + multis * 2 * imps ))                       # × enc(2)
  done
  expected=$(( roots * pools ))

  [ "$(printf '%s\n' "$cells" | grep -c .)" -eq "$expected" ]
  # exhaustive ⇒ every cell distinct.
  local total uniq
  total="$(jq -r '.id' <<<"$cells" | grep -c .)"
  uniq="$(jq -r '.id' <<<"$cells" | sort -u | grep -c .)"
  [ "$total" -eq "$uniq" ]
}

# ── AC2: every pinned seed is present; nvidia × kernel co-occurs ─────────────

@test "tier2: every pinned historical-bug seed is in the set" {
  local cells; cells="$(matrix_tier2_cells 0)"
  local id
  for id in seed-zfs-root-btrfs-pool seed-ext4-root-zfs-pool \
            seed-btrfs-raid1-enc-multi seed-xfs-root \
            seed-zfs-keyfile-root-enc-pool; do
    echo "$cells" | jq -e --arg id "$id" 'select(.id == $id)' >/dev/null
  done
  # nvidia × kernel co-occurs in ≥1 cell.
  echo "$cells" | jq -e 'select(.axes.gpu == "nvidia" and (.axes.kernel != null))' \
    >/dev/null
}

# ── AC5: every independent scalar value appears in at least one cell ─────────

@test "tier2: every scalar axis value appears in some cell" {
  local cells; cells="$(matrix_tier2_cells 0)"
  local axis val
  _has() { echo "$cells" | jq -e --arg a "$1" --argjson v "$2" \
    'select(.axes[$a] == $v)' >/dev/null; }
  _has kernel '"lts"';    _has kernel '"zen"'
  _has bootloader '"systemd-boot"'; _has bootloader '"grub"'
  _has desktop '"none"';  _has desktop '"kde"'
  _has gpu '"auto"'; _has gpu '"amd"'; _has gpu '"nvidia"'; _has gpu '"intel"'
  _has swap true;    _has swap false
}

# ── AC6: Tier-2 is deterministic for a fixed seed ───────────────────────────

@test "tier2: identical seed yields byte-identical output" {
  local a b
  a="$(matrix_tier2_cells 5)"
  b="$(matrix_tier2_cells 5)"
  [ "$a" = "$b" ]
}

# ── AC1 (Tier-2): no pairwise cell pairs a filesystem with an unreachable topology

@test "tier2: no cell violates filesystem↔topology reachability" {
  local cells; cells="$(matrix_tier2_cells 0)"
  local fs topo allowed
  while IFS=$'\t' read -r fs topo; do
    allowed=" single $(_matrix_multi_topologies "$fs" | tr '\n' ' ') "
    [[ "$allowed" == *" $topo "* ]] || { echo "bad: $fs/$topo"; false; }
  done < <(jq -r '"\(.axes.filesystem)\t\(.axes.topology)"' <<<"$cells" | sort -u)
}
