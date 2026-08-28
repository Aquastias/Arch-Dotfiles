#!/usr/bin/env bats
# Tests for `tools/matrix.sh gen` — the Combination Matrix records entry
# (combination-matrix/08, ADR 0046). `gen` regenerates the committed records:
# the Tier-2 Matrix Manifest (pairwise cover ∪ pinned seeds) and the coverage
# summary, after the Axis Registry gate. Behaviour under test is the written
# manifest's shape + reproducibility; the registry abort-on-gap is covered in
# matrix-registry.bats, the coverage summary in matrix-records.bats, and the
# cell-set properties in matrix-generator.bats.

setup() {
  MATRIX_SH="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/tools/matrix.sh"
  export INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # write records to the sandbox, never the committed repo files.
  export MATRIX_MANIFEST_PATH="$BATS_TEST_TMPDIR/manifest.jsonl"
  export MATRIX_COVERAGE_PATH="$BATS_TEST_TMPDIR/coverage.txt"
}

# ── gen writes a non-trivial manifest of well-formed cells ──────────────────

@test "gen: writes many JSON-lines cells, each with an id and axes object" {
  run bash "$MATRIX_SH" gen
  [ "$status" -eq 0 ]
  [ -f "$MATRIX_MANIFEST_PATH" ]
  [ -f "$MATRIX_COVERAGE_PATH" ]
  [ "$(grep -c . "$MATRIX_MANIFEST_PATH")" -gt 1 ]
  while IFS= read -r c; do
    echo "$c" | jq -e '.id and (.axes | type == "object")'
  done <"$MATRIX_MANIFEST_PATH"
}

# ── the manifest carries the pinned historical-bug seeds ────────────────────

@test "gen: the manifest includes the pinned seeds" {
  run bash "$MATRIX_SH" gen
  [ "$status" -eq 0 ]
  jq -e 'select(.id == "seed-xfs-root")' "$MATRIX_MANIFEST_PATH" >/dev/null
  jq -e 'select(.id == "seed-zfs-root-btrfs-pool")' \
    "$MATRIX_MANIFEST_PATH" >/dev/null
}

# ── gen is reproducible for a fixed seed ────────────────────────────────────

@test "gen: identical MATRIX_SEED yields byte-identical records" {
  MATRIX_SEED=3 bash "$MATRIX_SH" gen
  cp "$MATRIX_MANIFEST_PATH" "$BATS_TEST_TMPDIR/m1"
  cp "$MATRIX_COVERAGE_PATH" "$BATS_TEST_TMPDIR/c1"
  MATRIX_SEED=3 bash "$MATRIX_SH" gen
  diff "$BATS_TEST_TMPDIR/m1" "$MATRIX_MANIFEST_PATH"
  diff "$BATS_TEST_TMPDIR/c1" "$MATRIX_COVERAGE_PATH"
}
