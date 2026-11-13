#!/usr/bin/env bats
# Tests for the Combination Matrix Tier-2 driver cores (combination-matrix/06,
# ADR 0046): cell selection (smoke vs full), per-cell status classification, the
# run-all summary, and the aggregate exit code. Pure: sets/records in, decision
# out — the orchestrator's VM launch goes through an overridable seam so the
# run-all behaviour is exercised without a real VM.

setup() {
  INSTALLER_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export INSTALLER_DIR
  # shellcheck source=../../lib/matrix/driver.sh
  source "$INSTALLER_DIR/lib/matrix/driver.sh"
  # never touch the host's libvirt from a test
  _driver_cleanup_cell() { :; }
}

# ── AC4: --smoke runs only the pinned seeds ──────────────────────────────────

@test "run_select smoke: only the pinned seed-* cells" {
  local ids
  # The smoke cells' ids.
  ids="$(matrix_run_select smoke 0 | jq -r '.id')"
  [ -n "$ids" ]
  # every selected cell is a pinned seed…
  run bash -c "printf '%s\n' \"$ids\" | grep -cv '^seed-'"
  [ "$output" -eq 0 ]
  # …and the known regression seeds are present.
  printf '%s\n' "$ids" | grep -qx 'seed-zfs-keyfile-root-enc-pool'
  printf '%s\n' "$ids" | grep -qx 'seed-xfs-root'
}

@test "run_select full: whole pairwise cover ∪ seeds (superset of smoke)" {
  local full smoke
  # The full and the smoke selections' ids.
  full="$(matrix_run_select full 0 | jq -r '.id')"
  smoke="$(matrix_run_select smoke 0 | jq -r '.id')"
  # the pairwise rows (t2-*) are present…
  printf '%s\n' "$full" | grep -q '^t2-'
  # …the seeds are still there…
  printf '%s\n' "$full" | grep -qx 'seed-xfs-root'
  # …and full strictly outnumbers smoke.
  [ "$(printf '%s\n' "$full" | wc -l)" -gt \
    "$(printf '%s\n' "$smoke" | wc -l)" ]
}

# ── AC5: per-cell status classification (boot_verify × encryption × exit) ─────

@test "classify: nonzero installer exit → FAIL regardless of cell kind" {
  [ "$(matrix_run_classify true false 1)" = FAIL ]    # plain, install broke
  [ "$(matrix_run_classify false true 125)" = FAIL ]  # encrypted, install broke
  [ "$(matrix_run_classify true false 124)" = FAIL ]  # timeout
}

@test "classify: install-OK boot-verified cell → PASS" {
  [ "$(matrix_run_classify true false 0)" = PASS ]
}

@test "classify: install-OK gpu install-only cell → PASS (its full oracle)" {
  # gpu≠auto: boot_verify=false but not encrypted → install-only is final.
  [ "$(matrix_run_classify false false 0)" = PASS ]
}

@test "classify: install-OK encrypted cell → SKIP (boot deferred to 07)" {
  [ "$(matrix_run_classify false true 0)" = SKIP ]
}

# ── AC5: the aggregate exit code fails the run iff any cell FAILed ────────────

@test "run_exit_code: any FAIL → non-zero; only PASS/SKIP → zero" {
  local ok fail
  ok="$(printf '%s\n' '{"id":"a","status":"PASS"}' \
    '{"id":"b","status":"SKIP"}')"
  fail="$(printf '%s\n' '{"id":"a","status":"PASS"}' \
    '{"id":"b","status":"FAIL"}' '{"id":"c","status":"SKIP"}')"

  run matrix_run_exit_code < <(printf '%s\n' "$ok")
  [ "$status" -eq 0 ]
  run matrix_run_exit_code < <(printf '%s\n' "$fail")
  [ "$status" -ne 0 ]
}

# ── AC5: the summary shows every cell; a FAIL carries a re-run hint ───────────

# _rec <id> <axes> <oracle> <status> — a result record JSON line.
_rec() {
  local record='{id: $id, axes: $axes, oracle: $oracle, status: $status}'
  # One record line from the four fields.
  jq -c -n --arg id "$1" --arg axes "$2" --arg oracle "$3" --arg status "$4" \
    "$record"
}

@test "summary_format: lists all cells; FAIL row has a re-run hint, SKIP≠FAIL" {
  local records; records="$(printf '%s\n' \
    "$(_rec seed-xfs-root xfs/single/plain firstboot PASS)" \
    "$(_rec t2-zfs-mirror zfs/mirror/plain firstboot FAIL)" \
    "$(_rec seed-btrfs-raid1-enc-multi btrfs/raid1/enc install-only SKIP)")"
  run matrix_summary_format < <(printf '%s\n' "$records")
  [ "$status" -eq 0 ]
  # every cell id is present
  [[ "$output" == *seed-xfs-root* ]]
  [[ "$output" == *t2-zfs-mirror* ]]
  [[ "$output" == *seed-btrfs-raid1-enc-multi* ]]
  # the failing cell carries a copy-pasteable re-run hint
  [[ "$output" == *"matrix.sh run t2-zfs-mirror"* ]]
  # the skipped cell reads SKIP, not FAIL
  printf '%s\n' "$output" | grep 'seed-btrfs-raid1-enc-multi' | grep -q SKIP
  ! { printf '%s\n' "$output" | grep 'seed-btrfs-raid1-enc-multi' \
      | grep -q FAIL; }
}

# ── AC5 (integration): run-all survives a failure; VM launch is a seam ───────

@test "run_all: one failing cell doesn't abort; all run; summary + nonzero" {
  local test_directory="$BATS_TEST_TMPDIR"
  # a plain cell fixture (the axes the driver reads).
  _plain_cell() {
    local plain='{id: $id, axes: {filesystem: $fs, topology: "single",'
    plain+=' encryption: false, impermanence: false}}'
    # A plain single-disk cell with that id and filesystem.
    jq -c -n --arg id "$1" --arg fs "$2" "$plain"
  }
  # stub selection: three plain cells (real generator not needed here).
  matrix_run_select() {
    printf '%s\n' "$(_plain_cell c1 zfs)" "$(_plain_cell c2 ext4)" "$(_plain_cell c3 xfs)"
  }
  # stub the host-IO seams so the run neither probes nor blocks.
  _driver_preflight()  { return 0; }
  _driver_guard_gate() { return 0; }
  # stub the per-cell VM launch: record the attempt, fail only c2.
  _driver_run_cell() {
    local id
    # The cell's id.
    id="$(printf '%s\n' "$1" | jq -r .id)"
    echo "$id" >>"$test_directory/attempts"
    [[ "$id" == c2 ]] && return 1 || return 0
  }
  run matrix_run_all --smoke
  [ "$status" -ne 0 ]                                  # c2 failed the run
  [[ "$output" == *c1* ]] && [[ "$output" == *c2* ]] && [[ "$output" == *c3* ]]
  [[ "$output" == *"matrix.sh run c2"* ]]        # re-run hint for the fail
  [ "$(sort -u "$test_directory/attempts" | wc -l)" -eq 3 ]      # every cell was attempted
}

# 20261021: `run --local` backgrounds the repo server in this shell; counting
# every job made it fill the one default slot (ADR 0155), so the gate waited
# on the server forever and no cell ever launched.
@test "guard_gate: a non-cell background job never takes a cell's slot" {
  MATRIX_MAX_PARALLEL=1
  _driver_memory_available_kib() { echo $((64 * 1024 * 1024)); }
  sleep 5 &
  local stray=$! started=$SECONDS
  _driver_guard_gate
  kill "$stray" 2>/dev/null || true
  (( SECONDS - started < 3 ))
}

@test "run_all: finishes while a non-cell background job keeps running" {
  MATRIX_MAX_PARALLEL=1
  _driver_memory_available_kib() { echo $((64 * 1024 * 1024)); }
  _driver_preflight() { return 0; }
  matrix_run_select() {
    local cell='{"id":"c1","axes":{"filesystem":"zfs","topology":"single",'
    cell+='"encryption":false,"impermanence":false}}'
    printf '%s\n' "$cell"
  }
  _driver_run_cell() { return 0; }
  sleep 30 &
  local stray=$! started=$SECONDS
  run matrix_run_all --smoke
  kill "$stray" 2>/dev/null || true
  [ "$status" -eq 0 ]
  (( SECONDS - started < 10 ))
}

# 20261022: matrix.sh runs under `set -e`, so a failing cell killed its
# subshell before the record was written — the cell vanished from the summary
# and the run exited 0 with 38 of 55 cells unrun.
@test "run_all under set -e: a failing cell is a FAIL row, never dropped" {
  run bash -c '
    set -euo pipefail
    INSTALLER_DIR="$1"; source "$INSTALLER_DIR/lib/matrix/driver.sh"
    matrix_run_select() {
      local id
      for id in c1 c2; do
        jq -c -n --arg id "$id" "{id:\$id, axes:{filesystem:\"zfs\",
          topology:\"single\", encryption:false, impermanence:false}}"
      done
    }
    _driver_preflight() { return 0; }
    _driver_guard_gate() { return 0; }
    _driver_run_cell() { [[ "$(printf '%s\n' "$1" | jq -r .id)" != c2 ]]; }
    _driver_cleanup_cell() { :; }
    matrix_run_all --smoke' _ "$INSTALLER_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *FAIL*c2* ]]
  [[ "$output" == *"FAIL=1"* ]]
}

@test "run_all: a cell that left no record is a FAIL row" {
  matrix_run_select() {
    local cell='{"id":"c9","axes":{"filesystem":"zfs","topology":"single",'
    cell+='"encryption":false,"impermanence":false}}'
    printf '%s\n' "$cell"
  }
  _driver_preflight() { return 0; }
  _driver_guard_gate() { return 0; }
  _driver_run_one() { return 1; }
  run matrix_run_all --smoke
  [ "$status" -ne 0 ]
  [[ "$output" == *FAIL*c9* ]]
}

# 20261022: every cell kept its 80 GB+ disks, so a full run filled the host
# and the later cells could not be created. A passing cell's VM is deleted; a
# failing one is kept to debug.
@test "run_all: a passing cell's VM is cleaned up, a failing one kept" {
  local test_directory="$BATS_TEST_TMPDIR"
  matrix_run_select() {
    local id plain='{id: $id, axes: {filesystem: "zfs", topology: "single",'
    plain+=' encryption: false, impermanence: false}}'
    for id in ok1 bad1; do
      # A plain zfs cell with that id.
      jq -c -n --arg id "$id" "$plain"
    done
  }
  _driver_preflight() { return 0; }
  _driver_guard_gate() { return 0; }
  _driver_run_cell() { [[ "$(printf '%s\n' "$1" | jq -r .id)" == ok1 ]]; }
  _driver_cleanup_cell() { echo "$1" >>"$test_directory/cleaned"; }
  run matrix_run_all --smoke
  [ "$(cat "$test_directory/cleaned")" = ok1 ]
}
