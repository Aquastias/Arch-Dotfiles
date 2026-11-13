#!/usr/bin/env bats
# Tests for the Cell Generator + Constraint Model (combination-matrix/04, ADR
# 0046). Sourcing the menu's own option functions (_controller_topologies_for_filesystem,
# _controller_built_root_filesystems) + the axis registry + the pairwise reducer, it
# emits two cell sets:
#   Tier-1 = the exhaustive storage-cluster cross-product under the menu's
#            exclusions (incl. mixed-fs + per-group encryption cells).
#   Tier-2 = a pairwise cover over the install-affecting axes ∪ pinned seeds.
# Reachability comes only from the menu functions, so impossible cells are
# structurally excluded. Behaviour under test = the emitted cell SET's
# properties (validity, coverage, seeds, determinism).

load ../lib/json-helpers

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export INSTALLER_DIR
  # the generator + the real validation contract it must not violate.
  # shellcheck source=../../lib/matrix/generator.sh
  source "$INSTALLER_DIR/lib/matrix/generator.sh"
  # the REAL topology contract, so the cross-check can't drift from production.
  error() { return 1; }
  # shellcheck source=../../lib/config/validation.sh
  source "$INSTALLER_DIR/lib/config/validation.sh"
}

# ── tracer: Tier-1 is a real (non-trivial) set that includes the simplest cell

@test "tier1: emits many cells including the simplest zfs-single-plain" {
  run matrix_tier1_cells
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -gt 1 ]
  # every line is a well-formed cell
  while IFS= read -r c; do
    json_satisfies "$c" '.id and (.axes | type == "object")'
  done < <(printf '%s\n' "$output")
  # the tracer cell is present, unchanged in shape
  output_satisfies 'select(.id == "zfs-single-plain")
    | .axes.filesystem == "zfs" and .axes.topology == "single"
      and .axes.encryption == false and .axes.impermanence == false'
}

# ── AC1: no cell violates the real topology contract / single-disk rules ────

@test "tier1: every distinct root/pool topology passes _validation_topology_for_filesystem" {
  local cells; cells="$(matrix_tier1_cells)"

  # ext4/xfs cells are single-disk only (topology single, disk_count 1).
  local single_only='select(.axes.filesystem == "ext4"'
  single_only+=' or .axes.filesystem == "xfs")'
  single_only+=' | .axes.topology == "single" and .axes.disk_count == 1'
  # No ext4/xfs cell breaks single-disk.
  ! printf '%s\n' "$cells" | jq -c "$single_only" | grep -q false || return 1

  local multi_pair='select(.axes.mode == "multi")'
  multi_pair+=' | "\(.axes.filesystem)\t\(.axes.topology)"'
  local pool_pair='select(.axes.data_pool != null)'
  pool_pair+=' | "\(.axes.data_pool.filesystem)\t\(.axes.data_pool.topology)"'
  # every distinct MULTI (fs,topology) passes the real validator.
  local triple pool_filesystem pool_topology
  while IFS=$'\t' read -r pool_filesystem pool_topology; do
    run _validation_topology_for_filesystem os_pool "$pool_filesystem" "$pool_topology"
    [ "$status" -eq 0 ]
  # Each distinct multi-disk "filesystem<TAB>topology".
  done < <(printf '%s\n' "$cells" | jq -r "$multi_pair" | sort -u)

  # every distinct data-pool (fs,topology) passes the real validator.
  while IFS=$'\t' read -r pool_filesystem pool_topology; do
    run _validation_topology_for_filesystem data "$pool_filesystem" "$pool_topology"
    [ "$status" -eq 0 ]
  # Each distinct data pool "filesystem<TAB>topology".
  done < <(printf '%s\n' "$cells" | jq -r "$pool_pair" | sort -u)
}

# ── AC3: mixed-filesystem and per-group-encryption cells are present ────────

@test "tier1: mixed-fs and per-group-encryption cells exist" {
  local cells; cells="$(matrix_tier1_cells)"
  # zfs root + btrfs data pool (mixed-fs)
  json_satisfies "$cells" 'select(.axes.filesystem=="zfs"
    and .axes.data_pool.filesystem=="btrfs")'
  # ext4 root + zfs data pool (mixed-fs, the other direction)
  json_satisfies "$cells" 'select(.axes.filesystem=="ext4"
    and .axes.data_pool.filesystem=="zfs")'
  # root encrypted / pool plaintext AND its inverse (per-group encryption)
  json_satisfies "$cells" 'select(.axes.encryption==true
    and .axes.data_pool.encryption==false)'
  json_satisfies "$cells" 'select(.axes.encryption==false
    and .axes.data_pool.encryption==true)'
}

# ── AC4: Tier-1 equals the exhaustive cross-product under exclusions ────────

@test "tier1: cell count equals the exhaustive cross-product; ids unique" {
  local cells; cells="$(matrix_tier1_cells)"

  # recompute the expected size from the menu-derived factors (independently of
  # the nested generator loop).
  local filesystem roots=0 pools expected=0 multis imps multi_encs
  pools="$(_generator_data_pool_specs | wc -l)"
  for filesystem in $(_generator_root_filesystems); do
    multis=$(_generator_multi_topologies "$filesystem" | wc -l)
    imps=$(_generator_impermanence_values "$filesystem" | wc -l)
    # a multi-disk root offers encryption unless the menu locks it (btrfs)
    multi_encs=2
    menu_state_encryption_locked \
      "{\"filesystem\":\"$filesystem\",\"mode\":\"multi\"}" && multi_encs=1
    roots=$(( roots + (2 + multis * multi_encs) * imps ))   # single × enc(2)
  done
  expected=$(( roots * pools ))

  [ "$(printf '%s\n' "$cells" | grep -c .)" -eq "$expected" ]
  # exhaustive ⇒ every cell distinct.
  local total uniq
  local ids
  # The cells' ids, all and distinct.
  ids="$(printf '%s\n' "$cells" | jq -r '.id')"
  total="$(printf '%s\n' "$ids" | grep -c .)"
  # How many distinct ids.
  uniq="$(printf '%s\n' "$ids" | sort -u | grep -c .)"
  [ "$total" -eq "$uniq" ]
}

# ── AC2: every pinned seed is present; nvidia × kernel co-occurs ─────────────

@test "tier2: every pinned historical-bug seed is in the set" {
  local cells; cells="$(matrix_tier2_cells 0)"
  local id
  for id in seed-zfs-root-btrfs-pool seed-ext4-root-zfs-pool \
            seed-xfs-root \
            seed-zfs-keyfile-root-enc-pool; do
    json_satisfies "$cells" "select(.id == \"$id\")"
  done
  # nvidia × kernel co-occurs in ≥1 cell.
  json_satisfies "$cells" \
    'select(.axes.gpu == "nvidia" and (.axes.kernel != null))' \
    >/dev/null
}

# ── AC5: every independent scalar value appears in at least one cell ─────────

@test "tier2: every scalar axis value appears in some cell" {
  local cells; cells="$(matrix_tier2_cells 0)"
  local axis value
  # _has <axis> <json-value> — some cell has that axis value.
  _has() { json_satisfies "$cells" "select(.axes.$1 == $2)"; }
  _has kernel '"lts"';    _has kernel '"zen"'
  _has bootloader '"systemd-boot"'; _has bootloader '"grub"'
  _has desktop '"none"';  _has desktop '"kde"'
  _has gpu '"auto"'; _has gpu '"amd"'; _has gpu '"nvidia"'; _has gpu '"intel"'
  _has swap true;    _has swap false
}

# ── AC6: Tier-2 is deterministic for a fixed seed ───────────────────────────

@test "tier2: identical seed yields byte-identical output" {
  local first_run second_run
  first_run="$(matrix_tier2_cells 5)"
  second_run="$(matrix_tier2_cells 5)"
  [ "$first_run" = "$second_run" ]
}

# ── AC1 (Tier-2): no pairwise cell pairs a filesystem with an unreachable topology

@test "tier2: no cell violates filesystem↔topology reachability" {
  local cells; cells="$(matrix_tier2_cells 0)"
  local filesystem topology allowed
  while IFS=$'\t' read -r filesystem topology; do
    allowed=" single $(_generator_multi_topologies "$filesystem" | paste -sd' ' -) "
    [[ "$allowed" == *" $topology "* ]] || { echo "bad: $filesystem/$topology"; false; }
  # Each distinct "filesystem<TAB>topology".
  done < <(printf '%s\n' "$cells" \
      | jq -r '"\(.axes.filesystem)\t\(.axes.topology)"' | sort -u)
}

# 20261022: the menu locks encryption off on a multi-disk btrfs root (the
# layout refuses it), so no cell may carry the combination.
@test "no cell pairs encryption with a multi-disk btrfs root" {
  local cells
  cells="$(matrix_tier1_cells; matrix_tier2_cells 0)"
  local btrfs_multi_encrypted='select(.axes.filesystem == "btrfs"'
  btrfs_multi_encrypted+=' and .axes.mode == "multi" and .axes.encryption)'
  # No cell is an encrypted multi-disk btrfs root.
  ! printf '%s\n' "$cells" | jq -c "$btrfs_multi_encrypted" | grep -q .
}
