#!/usr/bin/env bats
# Tests for the Pairwise Reducer (combination-matrix/03, ADR 0046): a pure,
# menu-agnostic 2-wise covering-array builder. Input = axes (each with allowed
# values) + exclusion constraints; output = deterministic JSON-lines rows in
# which every valid value-pair co-occurs at least once and no excluded pair ever
# appears. Behaviour under test is the emitted row SET's properties (coverage,
# exclusion-respect, determinism) — never how the array is built (minimality is
# an implementation detail, not asserted).

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=../../lib/matrix/pairwise.sh
  source "$INSTALLER_DIR/lib/matrix/pairwise.sh"
}

# _covered <rows> <axisA> <valA> <axisB> <valB> — 0 iff some row assigns both.
# valA/valB are JSON tokens ("zfs" / false / 2).
_covered() {
  local rows="$1" ka="$2" va="$3" kb="$4" vb="$5"
  jq -e -n --argjson rows "[$(printf '%s' "$rows" | jq -s '.')]" \
    --arg ka "$ka" --argjson va "$va" --arg kb "$kb" --argjson vb "$vb" \
    '$rows[0] | any(.[]; .[$ka] == $va and .[$kb] == $vb)' >/dev/null
}

# ── tracer: two 2-value axes, no constraints → all four pairs appear ────────

@test "pairwise: two axes cover every value-pair (full cartesian)" {
  axes='{"fs":["zfs","btrfs"],"enc":[false,true]}'
  run matrix_pairwise "$axes" '[]' 0
  [ "$status" -eq 0 ]
  # each emitted row assigns both axes
  while IFS= read -r row; do
    echo "$row" | jq -e 'has("fs") and has("enc")'
  done <<<"$output"
  # every value-pair is covered
  _covered "$output" fs '"zfs"'  enc false
  _covered "$output" fs '"zfs"'  enc true
  _covered "$output" fs '"btrfs"' enc false
  _covered "$output" fs '"btrfs"' enc true
}

# ── every valid pair across three binary axes is covered ────────────────────

@test "pairwise: three axes cover every axis-pair's value-pairs" {
  axes='{"a":["x","y"],"b":["p","q"],"c":[1,2]}'
  run matrix_pairwise "$axes" '[]' 0
  [ "$status" -eq 0 ]
  local va vb pa pb
  # a×b, a×c, b×c — all four combos of each must appear
  for pa in '"x"' '"y"'; do for pb in '"p"' '"q"'; do
    _covered "$output" a "$pa" b "$pb"; done; done
  for pa in '"x"' '"y"'; do for pb in 1 2; do
    _covered "$output" a "$pa" c "$pb"; done; done
  for pa in '"p"' '"q"'; do for pb in 1 2; do
    _covered "$output" b "$pa" c "$pb"; done; done
}

# ── a constraint-excluded pair never appears ────────────────────────────────

@test "pairwise: an excluded value-pair appears in no row" {
  axes='{"fs":["zfs","btrfs","ext4"],"topology":["single","mirror"]}'
  cons='[{"fs":"ext4","topology":"mirror"}]'
  run matrix_pairwise "$axes" "$cons" 0
  [ "$status" -eq 0 ]
  # the forbidden combo is absent...
  ! _covered "$output" fs '"ext4"' topology '"mirror"'
  # ...while a valid pair sharing a value is still covered.
  _covered "$output" fs '"ext4"'  topology '"single"'
  _covered "$output" fs '"zfs"'   topology '"mirror"'
}

# ── determinism: identical axes + seed → byte-identical output ──────────────

@test "pairwise: identical input and seed is byte-identical" {
  axes='{"a":["x","y","z"],"b":["p","q"],"c":[1,2,3]}'
  local one two
  one="$(matrix_pairwise "$axes" '[]' 7)"
  two="$(matrix_pairwise "$axes" '[]' 7)"
  [ "$one" = "$two" ]
}

# ── single-value + heavily-constrained axes emit no impossible row ──────────

@test "pairwise: single-value axis + heavy constraints, no impossible rows" {
  # ext4 is single-disk only: forbid it with every non-single topology.
  axes='{"fs":["ext4"],"topology":["single","mirror","raidz1"],"enc":[false,true]}'
  cons='[{"fs":"ext4","topology":"mirror"},{"fs":"ext4","topology":"raidz1"}]'
  run matrix_pairwise "$axes" "$cons" 0
  [ "$status" -eq 0 ]
  # no row may pair ext4 with a forbidden topology
  ! _covered "$output" fs '"ext4"' topology '"mirror"'
  ! _covered "$output" fs '"ext4"' topology '"raidz1"'
  # the only feasible fs×topology pair is covered, and enc still varies
  _covered "$output" fs '"ext4"' topology '"single"'
  _covered "$output" topology '"single"' enc false
  _covered "$output" topology '"single"' enc true
}
