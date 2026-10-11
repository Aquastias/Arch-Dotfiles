#!/usr/bin/env bash
# =============================================================================
# lib/matrix/driver.sh — Combination Matrix Tier-2 run-all driver (ADR 0046)
# =============================================================================
# Turns the generated Tier-2 set into a scheduled, guarded, self-summarizing
# run. The pure cores — cell selection (smoke vs full), per-cell status
# classification, the summary table, and the aggregate exit code — are separated
# from the IO orchestrator (_driver_orchestrate, shared by matrix_run_all and
# matrix_smoke) so the run policy is unit-testable. The per-cell VM launch goes
# through the _driver_run_cell seam, which bats overrides to inject
# PASS/FAIL/SKIP without a real VM.
#
# Requires INSTALLER_DIR (menu functions, for the generator).
#
# Public API:
#   matrix_run_select <smoke|full> [seed]  → the selected Tier-2 cells (1/line)
#   matrix_run_classify <boot_verify> <encryption> <exit_code> → PASS|FAIL|SKIP
#   matrix_run_exit_code                → 1 iff any result line's status is FAIL
#   matrix_summary_format               → the run summary table (stdin → stdout)
#   matrix_run_all [--smoke|--full]     → guard, schedule, run-all, summarize
#   matrix_smoke_cells [seed]           → the curated boot set (issue 06)
#   matrix_smoke                        → guard, schedule, run the curated set
#
# Used by: tools/matrix.sh.
# =============================================================================

# shellcheck source=./generator.sh
declare -F matrix_tier2_cells >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/generator.sh"
# shellcheck source=./guard.sh
declare -F matrix_guard_max_parallel >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/guard.sh"
# shellcheck source=./synth.sh
declare -F matrix_cell_boot_verify >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/synth.sh"
# shellcheck source=./run.sh
declare -F matrix_run >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/run.sh"

# host-resource policy knobs (see ADR 0046 / issue 06); pure cores get these as
# args, the IO seams below read them.
: "${MATRIX_HOST_RESERVE_MB:=4096}"   # RAM held back for the host
: "${MATRIX_MAX_PARALLEL:=3}"         # hard cap on concurrent VMs
: "${MATRIX_VM_RAM_MB:=8192}"         # per-VM RAM (the synthesizer uses it)

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
# clean install: a boot-verified cell PASSes — encrypted cells included, since
# the Console Answerer unlocks them over serial (matrix issue 07, no
# install-only carve-out); a non-boot-verified plain cell (gpu≠auto,
# install-only) PASSes; a non-boot-verified encrypted cell SKIPs (boot-verify
# would be its only oracle).
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
  local failures
  failures="$(jq -s '[.[] | select(.status == "FAIL")] | length')" || return 2
  (( failures == 0 ))
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
  ' | _driver_align_columns
}

# _driver_align_columns — align TAB-separated rows like `column -t`: every
# column padded to its widest entry plus two spaces (short rows padded too),
# the last left unpadded, empty lines dropped.
_driver_align_columns() {
  awk '
    { line[NR] = $0; count = split($0, field, "\t")
      if (count > columns) columns = count
      for (i = 1; i <= count; i++)
        if (length(field[i]) > width[i]) width[i] = length(field[i]) }
    END {
      for (n = 1; n <= NR; n++) {
        if (line[n] == "") continue
        split(line[n], field, "\t"); out = ""
        for (i = 1; i <= columns; i++)
          out = out (i < columns \
            ? sprintf("%-" (width[i] + 2) "s", field[i]) : field[i])
        print out
      }
    }'
}

# ── IO seams (overridable in tests) ──────────────────────────────────────────

# _driver_memory_available_kib — the host's free RAM (KiB) from /proc/meminfo.
_driver_memory_available_kib() {
  awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo
}

# _driver_preflight — abort with a reason (nonzero) if the host cannot run any
# VM: no /dev/kvm, libvirtd down, or not even one VM's RAM free after the
# reserve. Runs once before any cell launches.
_driver_preflight() {
  local has_kvm=false up=false reason
  [[ -e /dev/kvm ]] && has_kvm=true
  systemctl is-active --quiet libvirtd 2>/dev/null && up=true
  # disk check is best-effort here; RAM is the binding constraint.
  reason="$(matrix_guard_preflight_reason "$has_kvm" "$up" \
    "$((1<<62))" 0)"
  [[ -z "$reason" ]] \
    || { echo "matrix: preflight abort — $reason" >&2; return 1; }
  local fit
  fit="$(matrix_guard_max_parallel "$(_driver_memory_available_kib)" \
    "$((MATRIX_HOST_RESERVE_MB*1024))" "$((MATRIX_VM_RAM_MB*1024))" \
    "$MATRIX_MAX_PARALLEL")"
  (( fit >= 1 )) || {
    echo "matrix: preflight abort — not one VM's RAM free after reserve" >&2
    return 1
  }
}

# _driver_guard_gate — block until a spawn slot is free: fewer than the cap
# running AND one VM's RAM available after the reserve.
_driver_guard_gate() {
  while :; do
    (( $(jobs -rp | grep -c .) < MATRIX_MAX_PARALLEL )) \
      && matrix_guard_can_launch "$(_driver_memory_available_kib)" \
           "$((MATRIX_HOST_RESERVE_MB*1024))" "$((MATRIX_VM_RAM_MB*1024))" \
      && return 0
    wait -n 2>/dev/null || sleep 2
  done
}

# _driver_run_cell <cell> — launch one cell's VM and return its exit code (0 ok,
# 124 timeout, 125 boot-fail). The default drives the real VM Harness via
# matrix_run; tests override this to inject an outcome without a VM.
_driver_run_cell() {
  matrix_run "$(jq -r '.id' <<<"$1")"
}

# _driver_run_one <cell> — run one cell and emit its result record JSON
# ({id,axes,oracle,status}) on stdout. Classifies the VM exit per the oracle.
# ONLY the JSON record may reach stdout (the orchestrator captures it as the
# cell's result file), so the VM launch's own verbose output is sent to stderr —
# otherwise it pollutes the record and the summary jq chokes.
_driver_run_one() {
  local cell="$1" id boot_verify encryption impermanence rc oracle axes status
  id="$(jq -r '.id' <<<"$cell")"
  boot_verify="$(matrix_cell_boot_verify "$cell")"
  encryption="$(jq -r '.axes.encryption // false' <<<"$cell")"
  impermanence="$(jq -r '.axes.impermanence // false' <<<"$cell")"
  _driver_run_cell "$cell" >&2; rc=$?
  status="$(matrix_run_classify "$boot_verify" "$encryption" "$rc")"
  if [[ "$boot_verify" == true ]]; then
    [[ "$impermanence" == true ]] && oracle=rollback || oracle=firstboot
  else
    oracle="install-only"
  fi
  axes="$(jq -r '.axes | "\(.filesystem)/\(.topology // "single")/"
    + (if .encryption then "enc" else "plain" end)' <<<"$cell")"
  jq -c -n --arg id "$id" --arg axes "$axes" --arg oracle "$oracle" \
    --arg status "$status" '{id:$id,axes:$axes,oracle:$oracle,status:$status}'
}

# _driver_orchestrate — read JSON cells on stdin, preflight the host, then
# schedule them up to the parallel cap (gated on free RAM), run each through the
# VM seam, and print the summary. One failing cell never aborts the others;
# returns non-zero iff any cell FAILed. Shared by matrix_run_all and
# matrix_smoke so both get identical guard/scheduling/summary behaviour.
_driver_orchestrate() {
  _driver_preflight || return $?

  local work launched=0 cell
  work="$(mktemp -d)"
  while IFS= read -r cell; do
    [[ -n "$cell" ]] || continue
    _driver_guard_gate
    ( _driver_run_one "$cell" >"$work/$(printf '%06d' "$launched").json" ) &
    launched=$((launched+1))
  done
  wait

  local records; records="$(cat "$work"/*.json 2>/dev/null)"
  rm -rf "$work"
  printf '%s\n' "$records" | matrix_summary_format
  printf '%s\n' "$records" | matrix_run_exit_code
}

# matrix_run_all [--smoke|--full] — the Tier-2 orchestrator: run the pinned
# seeds (--smoke, default) or the whole pairwise cover (--full) through the
# guarded scheduler. Exits non-zero iff any cell FAILed.
matrix_run_all() {
  local mode=smoke
  case "${1:-}" in
    --smoke) mode=smoke ;; --full) mode=full ;;
    "" ) : ;; *) echo "matrix: unknown run flag '$1'" >&2; return 2 ;;
  esac
  _driver_orchestrate < <(matrix_run_select "$mode" "${MATRIX_SEED:-0}")
}

# The curated on-demand boot set (ADR 0048, issue 06): a representative plain
# single, a mirror, impermanence, and an encrypted single. Distinct from
# --smoke's historical-bug seeds — this proves a basic install of each core
# shape still boots. Encrypted boot-verify runs through the Console Answerer via
# the VM Harness, exactly as its plain peer.
MATRIX_SMOKE_IDS=(
  zfs-single-plain       # a basic single-disk zfs install
  zfs-mirror-plain       # multi-disk mirror
  zfs-single-plain-imp   # impermanence (verify.rollback)
  zfs-single-enc         # encrypted single (Console Answerer unlock)
)

# matrix_smoke_cells [seed] — the curated smoke cells as JSON (one per line),
# drawn from the real generator by id so their axes/oracle stay menu-derived.
# Fails loud (rather than silently under-selecting) if a curated id no longer
# exists in the generator — e.g. after a cell-id rename.
matrix_smoke_cells() {
  local seed="${1:-0}" ids out count
  ids="$(printf '%s\n' "${MATRIX_SMOKE_IDS[@]}" | jq -R . | jq -sc .)"
  out="$(matrix_all_cells "$seed" \
    | jq -c --argjson ids "$ids" 'select(.id as $i | $ids | index($i))')"
  count="$(grep -c . <<<"$out")"
  if (( count != ${#MATRIX_SMOKE_IDS[@]} )); then
    echo \
      "matrix: smoke selected $count cells, expected ${#MATRIX_SMOKE_IDS[@]}" \
         "(a curated cell id no longer exists in the generator?)" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

# matrix_smoke — run the curated boot set through the shared guarded scheduler.
# On-demand only (needs libvirt+KVM); exits non-zero iff any cell FAILed.
matrix_smoke() {
  _driver_orchestrate < <(matrix_smoke_cells "${MATRIX_SEED:-0}")
}
