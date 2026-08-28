#!/usr/bin/env bats
# Tests for the committed Combination Matrix records (combination-matrix/08,
# ADR 0046): the Tier-2 Matrix Manifest and the coverage summary. The coverage
# summary is the drift guard for the constraint model — a diffable snapshot of
# resolved axes → values → exclusions + per-tier cell counts, so a silent shrink
# (fewer valid cells) shows as a one-line change, not a wall of vanished rows.

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export INSTALLER_DIR
  # shellcheck source=../../lib/matrix/records.sh
  source "$INSTALLER_DIR/lib/matrix/records.sh"
}

# ── AC1/AC2: the coverage summary is sectioned + deterministic ───────────────

@test "coverage: sectioned (axes/exclusions/counts), topology on one line" {
  local s; s="$(matrix_coverage_summary)"
  printf '%s\n' "$s" | grep -qx '\[axes\]'
  printf '%s\n' "$s" | grep -qx '\[exclusions\]'
  printf '%s\n' "$s" | grep -qx '\[counts\]'
  # topology values live on a single sorted line (AC4 shape)
  local topo; topo="$(printf '%s\n' "$s" | grep -E '^topology: ')"
  [ -n "$topo" ]
  [[ "$topo" == *single* && "$topo" == *raidz2* && "$topo" == *mirror* ]]
}

@test "coverage: byte-identical across runs for the same seed" {
  [ "$(MATRIX_SEED=2 matrix_coverage_summary)" \
    = "$(MATRIX_SEED=2 matrix_coverage_summary)" ]
}

@test "coverage: counts equal the actually generated sets" {
  local s; s="$(matrix_coverage_summary 0)"
  local t1 t2 t2p t2s
  t1="$(printf '%s\n' "$s" | sed -n 's/^tier1: //p')"
  t2="$(printf '%s\n' "$s" | sed -n 's/^tier2-total: //p')"
  t2p="$(printf '%s\n' "$s" | sed -n 's/^tier2-pairwise: //p')"
  t2s="$(printf '%s\n' "$s" | sed -n 's/^tier2-seeds: //p')"
  [ "$t1" -eq "$(matrix_tier1_cells | grep -c .)" ]
  [ "$t2" -eq "$(matrix_tier2_cells 0 | grep -c .)" ]
  [ "$((t2p + t2s))" -eq "$t2" ]          # breakdown sums to the total
  [ "$t2s" -gt 0 ]                        # the pinned seeds are counted
}

# ── AC4: a dropped topology value is a one-line summary change, not a wall ────

# extract the [axes] section (between its header and the blank line).
_axes_section() { printf '%s\n' "$1" | sed -n '/^\[axes\]$/,/^$/p'; }

@test "coverage: dropping a topology value → one [axes] line changes" {
  local full reduced
  full="$(matrix_coverage_summary 0)"
  # shrink the constraint model: drop raidz2 from the pairwise topology domain.
  _TEST_BASE_AXES="$(_matrix_tier2_axes)"
  _matrix_tier2_axes() {
    jq -c '.topology -= ["raidz2"]' <<<"$_TEST_BASE_AXES"
  }
  reduced="$(matrix_coverage_summary 0)"
  # only the topology line differs in [axes]: diff shows one < and one >.
  local n; n="$(diff <(_axes_section "$full") <(_axes_section "$reduced") \
    | grep -cE '^[<>]')"
  [ "$n" -eq 2 ]
  printf '%s\n' "$full"    | grep -E '^topology: ' | grep -q raidz2
  printf '%s\n' "$reduced" | grep -E '^topology: ' | grep -qv raidz2
}

# ── the manifest is the Tier-2 set, one cell per line, sorted by id ──────────

@test "manifest: cells carry id + axes and are sorted by id" {
  local m; m="$(matrix_manifest 0)"
  [ "$(printf '%s\n' "$m" | grep -c .)" -gt 1 ]
  while IFS= read -r c; do
    echo "$c" | jq -e '.id and (.axes | type == "object")'
  done <<<"$m"
  # ids are in a stable, deterministic order for clean diffs (jq unique_by
  # sorts by codepoint; compare with byte-order sort, not locale collation).
  local ids; ids="$(printf '%s\n' "$m" | jq -r '.id')"
  [ "$ids" = "$(printf '%s\n' "$ids" | LC_ALL=C sort)" ]
}

# ── AC3: the committed records are CI-enforced against a fresh regeneration ───

@test "drift guard: committed records match a fresh regen at the pinned seed" {
  matrix_manifest 0 >"$BATS_TEST_TMPDIR/m"
  matrix_coverage_summary 0 >"$BATS_TEST_TMPDIR/c"
  diff "$INSTALLER_DIR/tests/vm/matrix-manifest.jsonl" "$BATS_TEST_TMPDIR/m"
  diff "$INSTALLER_DIR/tests/vm/matrix-coverage.txt" "$BATS_TEST_TMPDIR/c"
}

@test "drift guard: a deliberate axis-value change is detected (fails CI)" {
  # simulate a menu/constraint change: drop raidz2 from the pairwise axes.
  _TEST_BASE_AXES="$(_matrix_tier2_axes)"
  _matrix_tier2_axes() {
    jq -c '.topology -= ["raidz2"]' <<<"$_TEST_BASE_AXES"
  }
  matrix_coverage_summary 0 >"$BATS_TEST_TMPDIR/c"
  # the regen now diverges from the committed snapshot → CI would fail.
  ! diff -q "$INSTALLER_DIR/tests/vm/matrix-coverage.txt" "$BATS_TEST_TMPDIR/c" \
    >/dev/null
}
