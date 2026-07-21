#!/usr/bin/env bats
# Tests for `matrix.sh smoke` — the curated on-demand boot set (ADR 0048, issue
# 06). Distinct from `run --smoke` (the pinned historical-bug seeds): this is a
# small representative set — a plain single, a mirror, impermanence, and an
# encrypted single — proving a basic install of each core shape still boots.
#
# The selection is exercised against the real generator; the orchestration is
# exercised through the same VM/host seams the run-all driver uses, so no real
# VM runs here.

setup() {
  OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export OS_DIR
  # shellcheck source=../../lib/matrix/driver.sh
  source "$OS_DIR/lib/matrix/driver.sh"
}

# ── selection: exactly the curated cells, drawn from the real generator ───────

@test "smoke_cells: exactly the four curated cell ids" {
  local ids; ids="$(matrix_smoke_cells 0 | jq -r '.id' | sort)"
  local want; want="$(printf '%s\n' \
    zfs-mirror-plain zfs-single-enc zfs-single-plain zfs-single-plain-imp)"
  [ "$ids" = "$want" ]
}

@test "smoke_cells: every selected cell is a real generator cell (has axes)" {
  run bash -c "source '$OS_DIR/lib/matrix/driver.sh'
    matrix_smoke_cells 0 | jq -e '.axes.filesystem' >/dev/null"
  [ "$status" -eq 0 ]
}

# ── orchestration: reuses the guarded run-all machinery via a shared core ─────

@test "smoke: runs every curated cell; a failure doesn't abort; nonzero exit" {
  local tmp="$BATS_TEST_TMPDIR"
  _pcell() {
    jq -c -n --arg id "$1" '{id:$id, axes:{filesystem:"zfs",
      topology:"single", encryption:false, impermanence:false}}'
  }
  # stub selection → four plain cells (real generator not needed here).
  matrix_smoke_cells() {
    printf '%s\n' "$(_pcell zfs-single-plain)" "$(_pcell zfs-mirror-plain)" \
      "$(_pcell zfs-single-plain-imp)" "$(_pcell zfs-single-enc)"
  }
  _matrix_preflight()  { return 0; }
  _matrix_guard_gate() { return 0; }
  _matrix_run_cell() {
    local id; id="$(jq -r .id <<<"$1")"
    echo "$id" >>"$tmp/attempts"
    [[ "$id" == zfs-mirror-plain ]] && return 1 || return 0   # one fails
  }
  run matrix_smoke
  [ "$status" -ne 0 ]                                   # the failing cell fails
  [[ "$output" == *zfs-single-plain* ]]
  [[ "$output" == *zfs-mirror-plain* ]]
  [[ "$output" == *zfs-single-plain-imp* ]]
  [[ "$output" == *zfs-single-enc* ]]
  [[ "$output" == *"matrix.sh run zfs-mirror-plain"* ]]  # re-run hint on fail
  [ "$(sort -u "$tmp/attempts" | wc -l)" -eq 4 ]         # all four attempted
}
