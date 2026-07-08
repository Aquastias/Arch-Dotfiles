#!/usr/bin/env bats
# Tests for `tools/matrix.sh gen` — the Combination Matrix generator
# (combination-matrix/01, ADR 0046). Tracer-bullet slice: `gen` emits the
# manifest of matrix cells as JSON lines, one cell per line, each carrying a
# stable cell-id plus its axis assignment. For this slice the manifest is the
# single simplest cell (zfs root, single disk, unencrypted, no desktop) — no
# axis fan-out yet. Behaviour under test is the emitted manifest, never how the
# generator builds it.

setup() {
  MATRIX_SH="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/tools/matrix.sh"
  export OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# ── tracer: gen emits exactly one cell line, well-formed JSON ────────────────

@test "gen: emits one JSON-lines cell with an id and an axes object" {
  run bash "$MATRIX_SH" gen
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  echo "$output" | jq -e '.id and (.axes | type == "object")'
}

# ── the tracer cell is the simplest storage cell ────────────────────────────

@test "gen: the tracer cell is zfs / single / unencrypted / no desktop" {
  run bash "$MATRIX_SH" gen
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.axes.filesystem == "zfs"'
  echo "$output" | jq -e '.axes.topology == "single"'
  echo "$output" | jq -e '.axes.encryption == false'
  echo "$output" | jq -e '(.axes.desktop | length) == 0'
}
