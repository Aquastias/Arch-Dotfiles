#!/usr/bin/env bash
# =============================================================================
# lib/matrix/driver.sh — Combination Matrix Tier-2 run-all driver (ADR 0046)
# =============================================================================
# Turns the generated Tier-2 set into a scheduled, guarded, self-summarizing
# run. The pure cores — cell selection (smoke vs full), per-cell status
# classification, the summary table, and the aggregate exit code — are separated
# from the IO orchestrator (matrix_run_all) so the run-all policy is unit-
# testable. The per-cell VM launch goes through the _matrix_run_cell seam, which
# bats overrides to inject PASS/FAIL/SKIP without a real VM.
#
# Requires OS_DIR (menu functions, for the generator).
#
# Public API:
#   matrix_run_select <smoke|full> [seed]  → the selected Tier-2 cells (1/line)
#   matrix_run_classify <boot_verify> <encryption> <exit_code> → PASS|FAIL|SKIP
#   matrix_run_exit_code                → 1 iff any result line's status is FAIL
#   matrix_summary_format               → the run summary table (stdin → stdout)
#   matrix_run_all [--smoke|--full]     → guard, schedule, run-all, summarize
# =============================================================================

# shellcheck source=./generator.sh
[[ "$(type -t matrix_tier2_cells)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/generator.sh"
# shellcheck source=./guard.sh
[[ "$(type -t matrix_guard_max_parallel)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/guard.sh"
# shellcheck source=./synth.sh
[[ "$(type -t matrix_cell_boot_verify)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/synth.sh"
# shellcheck source=./run.sh
[[ "$(type -t matrix_run)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/run.sh"

# host-resource policy knobs (see ADR 0046 / issue 06); pure cores get these as
# args, the IO seams below read them.
: "${MATRIX_HOST_RESERVE_MB:=4096}"   # RAM held back for the host
: "${MATRIX_MAX_PARALLEL:=3}"         # hard cap on concurrent VMs
: "${MATRIX_VM_RAM_MB:=8192}"         # per-VM RAM (matches the synthesizer)

# matrix_run_select <smoke|full> [seed] — the Tier-2 cells to run, one JSON cell
# per line. smoke = the pinned historical-bug seeds only (seed-*); full = the
# whole pairwise cover ∪ seeds. MATRIX_SEED-equivalent draw is pinned by [seed].
matrix_run_select() {
  local mode="$1" seed="${2:-0}"
  case "$mode" in
    smoke) matrix_tier2_cells "$seed" \
             | jq -c 'select(.id | startswith("seed-"))' ;;
    full)  matrix_tier2_cells "$seed" ;;
    *) echo "matrix: unknown select mode '$mode'" >&2; return 2 ;;
  esac
}

# matrix_run_classify <boot_verify> <encryption> <exit_code> — cell status.
# A nonzero VM exit (installer error, timeout, boot-fail) is always FAIL. On a
# clean install: a boot-verified cell PASSes; an install-only gpu cell PASSes
# (INSTALLER-EXIT-0 is its whole oracle); an encrypted cell SKIPs, because its
# real oracle is boot-verify, deferred to issue 07 (a flip to PASS then).
matrix_run_classify() {
  local boot_verify="$1" encryption="$2" exit_code="$3"
  (( exit_code != 0 )) && { echo FAIL; return; }
  if [[ "$boot_verify" == true ]]; then echo PASS; return; fi
  [[ "$encryption" == true ]] && echo SKIP || echo PASS
}

# matrix_run_exit_code — read result JSON lines ({id,status,…}) on stdin; exit 1
# iff any cell FAILed (PASS and SKIP are both non-failing), else 0. A single bad
# cell fails the run without hiding the others (they are already in the record).
matrix_run_exit_code() {
  local n
  n="$(jq -s '[.[] | select(.status == "FAIL")] | length')" || return 2
  (( n == 0 ))
}

# matrix_summary_format — read result JSON lines ({id,axes,oracle,status}) on
# stdin; print the run summary: one aligned row per cell (status · id · axes ·
# oracle) followed by a re-run hint under every FAIL, then a PASS/FAIL/SKIP
# tally. Every cell appears, so one failure never hides the rest.
matrix_summary_format() {
  jq -r -s '
    (.[] | "\(.status)\t\(.id)\t\(.axes)\t\(.oracle)"
       + (if .status == "FAIL"
          then "\n      re-run: matrix.sh run \(.id)" else "" end)),
    "----",
    "totals: PASS=\([.[]|select(.status=="PASS")]|length)"
      + " FAIL=\([.[]|select(.status=="FAIL")]|length)"
      + " SKIP=\([.[]|select(.status=="SKIP")]|length)"
  ' | column -t -s $'\t' 2>/dev/null || jq -r -s '.[] | "\(.status) \(.id)"'
}

# ── IO seams (overridable in tests) ──────────────────────────────────────────

# _matrix_mem_available_kib — the host's free RAM (KiB) from /proc/meminfo.
_matrix_mem_available_kib() {
  awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo
}

# _matrix_preflight — abort with a reason (nonzero) if the host cannot run any
# VM: no /dev/kvm, libvirtd down, or not even one VM's RAM free after the
# reserve. Runs once before any cell launches.
_matrix_preflight() {
  local has_kvm=false up=false reason
  [[ -e /dev/kvm ]] && has_kvm=true
  systemctl is-active --quiet libvirtd 2>/dev/null && up=true
  # disk check is best-effort here; RAM is the binding constraint.
  reason="$(matrix_guard_preflight_reason "$has_kvm" "$up" \
    "$((1<<62))" 0)"
  [[ -z "$reason" ]] \
    || { echo "matrix: preflight abort — $reason" >&2; return 1; }
  local fit
  fit="$(matrix_guard_max_parallel "$(_matrix_mem_available_kib)" \
    "$((MATRIX_HOST_RESERVE_MB*1024))" "$((MATRIX_VM_RAM_MB*1024))" \
    "$MATRIX_MAX_PARALLEL")"
  (( fit >= 1 )) || {
    echo "matrix: preflight abort — not one VM's RAM free after reserve" >&2
    return 1
  }
}

# _matrix_guard_gate — block until a spawn slot is free: fewer than the cap
# running AND one VM's RAM available after the reserve.
_matrix_guard_gate() {
  while :; do
    (( $(jobs -rp | wc -l) < MATRIX_MAX_PARALLEL )) \
      && matrix_guard_can_launch "$(_matrix_mem_available_kib)" \
           "$((MATRIX_HOST_RESERVE_MB*1024))" "$((MATRIX_VM_RAM_MB*1024))" \
      && return 0
    wait -n 2>/dev/null || sleep 2
  done
}

# _matrix_run_cell <cell> — launch one cell's VM and return its exit code (0 ok,
# 124 timeout, 125 boot-fail). The default drives the real VM Harness via
# matrix_run; tests override this to inject an outcome without a VM.
_matrix_run_cell() {
  matrix_run "$(jq -r '.id' <<<"$1")"
}

# _matrix_run_one <cell> — run one cell and emit its result record JSON
# ({id,axes,oracle,status}) on stdout. Classifies the VM exit per the oracle.
_matrix_run_one() {
  local cell="$1" id bv enc imp rc oracle axes status
  id="$(jq -r '.id' <<<"$cell")"
  bv="$(matrix_cell_boot_verify "$cell")"
  enc="$(jq -r '.axes.encryption // false' <<<"$cell")"
  imp="$(jq -r '.axes.impermanence // false' <<<"$cell")"
  _matrix_run_cell "$cell"; rc=$?
  status="$(matrix_run_classify "$bv" "$enc" "$rc")"
  if [[ "$bv" == true ]]; then
    [[ "$imp" == true ]] && oracle=rollback || oracle=firstboot
  else
    oracle=install-only
  fi
  axes="$(jq -r '.axes | "\(.filesystem)/\(.topology // "single")/"
    + (if .encryption then "enc" else "plain" end)' <<<"$cell")"
  jq -c -n --arg id "$id" --arg axes "$axes" --arg oracle "$oracle" \
    --arg status "$status" '{id:$id,axes:$axes,oracle:$oracle,status:$status}'
}

# matrix_run_all [--smoke|--full] — the Tier-2 orchestrator: preflight the host,
# schedule the selected cells up to the parallel cap (gated on free RAM), run
# each through the VM seam, then print the summary. One failing cell never
# aborts the others; exits non-zero iff any cell FAILed. Default: --smoke.
matrix_run_all() {
  local mode=smoke
  case "${1:-}" in
    --smoke) mode=smoke ;; --full) mode=full ;;
    "" ) : ;; *) echo "matrix: unknown run flag '$1'" >&2; return 2 ;;
  esac

  _matrix_preflight || return $?

  local work n=0 cell
  work="$(mktemp -d)"
  while IFS= read -r cell; do
    [[ -n "$cell" ]] || continue
    _matrix_guard_gate
    ( _matrix_run_one "$cell" >"$work/$(printf '%06d' "$n").json" ) &
    n=$((n+1))
  done < <(matrix_run_select "$mode" "${MATRIX_SEED:-0}")
  wait

  local recs; recs="$(cat "$work"/*.json 2>/dev/null)"
  rm -rf "$work"
  printf '%s\n' "$recs" | matrix_summary_format
  printf '%s\n' "$recs" | matrix_run_exit_code
}
