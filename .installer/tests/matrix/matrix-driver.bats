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
}

# ── AC4: --smoke runs only the pinned seeds ──────────────────────────────────

@test "run_select smoke: only the pinned seed-* cells" {
  local ids; ids="$(matrix_run_select smoke 0 | jq -r '.id')"
  [ -n "$ids" ]
  # every selected cell is a pinned seed…
  run bash -c "printf '%s\n' \"$ids\" | grep -cv '^seed-'"
  [ "$output" -eq 0 ]
  # …and the known regression seeds are present.
  printf '%s\n' "$ids" | grep -qx 'seed-btrfs-raid1-enc-multi'
  printf '%s\n' "$ids" | grep -qx 'seed-xfs-root'
}

@test "run_select full: whole pairwise cover ∪ seeds (superset of smoke)" {
  local full smoke; full="$(matrix_run_select full 0 | jq -r '.id')"
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

  run matrix_run_exit_code <<<"$ok"
  [ "$status" -eq 0 ]
  run matrix_run_exit_code <<<"$fail"
  [ "$status" -ne 0 ]
}

# ── AC5: the summary shows every cell; a FAIL carries a re-run hint ───────────

# _rec <id> <axes> <oracle> <status> — a result record JSON line.
_rec() {
  jq -c -n --arg id "$1" --arg axes "$2" --arg oracle "$3" --arg status "$4" \
    '{id:$id, axes:$axes, oracle:$oracle, status:$status}'
}

@test "summary_format: lists all cells; FAIL row has a re-run hint, SKIP≠FAIL" {
  local recs; recs="$(printf '%s\n' \
    "$(_rec seed-xfs-root xfs/single/plain firstboot PASS)" \
    "$(_rec t2-zfs-mirror zfs/mirror/plain firstboot FAIL)" \
    "$(_rec seed-btrfs-raid1-enc-multi btrfs/raid1/enc install-only SKIP)")"
  run matrix_summary_format <<<"$recs"
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
  local tmp="$BATS_TEST_TMPDIR"
  # a plain cell fixture (the axes the driver reads).
  _pcell() {
    jq -c -n --arg id "$1" --arg fs "$2" '{id:$id, axes:{filesystem:$fs,
      topology:"single", encryption:false, impermanence:false}}'
  }
  # stub selection: three plain cells (real generator not needed here).
  matrix_run_select() {
    printf '%s\n' "$(_pcell c1 zfs)" "$(_pcell c2 ext4)" "$(_pcell c3 xfs)"
  }
  # stub the host-IO seams so the run neither probes nor blocks.
  _matrix_preflight()  { return 0; }
  _matrix_guard_gate() { return 0; }
  # stub the per-cell VM launch: record the attempt, fail only c2.
  _matrix_run_cell() {
    local id; id="$(jq -r .id <<<"$1")"
    echo "$id" >>"$tmp/attempts"
    [[ "$id" == c2 ]] && return 1 || return 0
  }
  run matrix_run_all --smoke
  [ "$status" -ne 0 ]                                  # c2 failed the run
  [[ "$output" == *c1* ]] && [[ "$output" == *c2* ]] && [[ "$output" == *c3* ]]
  [[ "$output" == *"matrix.sh run c2"* ]]        # re-run hint for the fail
  [ "$(sort -u "$tmp/attempts" | wc -l)" -eq 3 ]      # every cell was attempted
}
