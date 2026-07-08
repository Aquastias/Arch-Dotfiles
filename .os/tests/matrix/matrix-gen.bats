#!/usr/bin/env bats
# Tests for `tools/matrix.sh gen` — the Combination Matrix generator entry
# (combination-matrix, ADR 0046). `gen` emits the committed Tier-2 Matrix
# Manifest (pairwise cover ∪ pinned seeds) as JSON lines, after the Axis
# Registry gate. Behaviour under test is the emitted manifest's shape +
# reproducibility; the registry abort-on-gap is covered in matrix-registry.bats,
# and the cell-set properties in matrix-generator.bats.

setup() {
  MATRIX_SH="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/tools/matrix.sh"
  export OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# ── gen emits a non-trivial manifest of well-formed cells ───────────────────

@test "gen: emits many JSON-lines cells, each with an id and axes object" {
  run bash "$MATRIX_SH" gen
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -gt 1 ]
  while IFS= read -r c; do
    echo "$c" | jq -e '.id and (.axes | type == "object")'
  done <<<"$output"
}

# ── the manifest carries the pinned historical-bug seeds ────────────────────

@test "gen: the manifest includes the pinned seeds" {
  run bash "$MATRIX_SH" gen
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'select(.id == "seed-xfs-root")' >/dev/null
  echo "$output" | jq -e 'select(.id == "seed-zfs-root-btrfs-pool")' >/dev/null
}

# ── gen is reproducible for a fixed seed ────────────────────────────────────

@test "gen: identical MATRIX_SEED yields byte-identical output" {
  local a b
  a="$(MATRIX_SEED=3 bash "$MATRIX_SH" gen)"
  b="$(MATRIX_SEED=3 bash "$MATRIX_SH" gen)"
  [ "$a" = "$b" ]
}
