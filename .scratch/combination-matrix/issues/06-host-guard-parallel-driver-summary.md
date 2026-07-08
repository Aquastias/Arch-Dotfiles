# 06 — Host-resource guard + parallel driver + summary

Status: done
Type: AFK

## Resolved decisions

- Host reserve: `MATRIX_HOST_RESERVE_MB` (default 4096), arg to the pure core.
- Parallel cap: `MATRIX_MAX_PARALLEL` (default 3), the clamp arg.
- SKIP semantics: encrypted install-OK ⇒ SKIP (flips to PASS in issue 07);
  gpu≠auto install-OK ⇒ PASS (install-only is its full oracle); nonzero VM exit
  ⇒ FAIL; unscheduled ⇒ SKIP. Pure classifier `matrix_run_classify`.
- Default run mode = `--smoke`; `matrix.sh run <cell-id>` stays single-cell.

## Implementation

- `lib/matrix/guard.sh` — pure cores: `matrix_guard_max_parallel`,
  `matrix_guard_preflight_reason`, `matrix_guard_can_launch`.
- `lib/matrix/driver.sh` — `matrix_run_select`, `matrix_run_classify`,
  `matrix_run_exit_code`, `matrix_summary_format`, and `matrix_run_all` wiring
  IO seams (`_matrix_preflight`, `_matrix_guard_gate`, `_matrix_run_cell`).
- Tests: `tests/matrix/matrix-guard.bats` (5), `matrix-driver.bats` (9).
- Live: `matrix.sh run --smoke` on a kvm-less host aborts with a clear reason,
  exit 1, no hang (AC2 verified end-to-end).

## Parent

`.scratch/combination-matrix/PRD.md`

## What to build

Make `matrix.sh run` a real orchestrator that never freezes the host:

- **Host-resource guard** (pure decision core) — preflight computes
  `max_parallel` from `MemAvailable` minus a host reserve, divided by per-VM RAM
  (8 GiB), and checks `/dev/kvm`, `libvirtd`, and free image-dir disk; it aborts
  with a structured reason if even one VM can't fit. A per-launch gate re-checks
  before each spawn and blocks until a running cell frees RAM rather than
  over-committing.
- **Parallel driver** — schedules cells up to `max_parallel` (default cap 3),
  `--smoke` (pinned seeds only) vs `--full` (whole pairwise set).
- **Run-all + summary** — one failing cell never aborts the others; collect all
  results, print a summary table (cell-id · axes · oracle · PASS/FAIL/SKIP, with
  a re-run hint per failure), and exit non-zero if any cell failed. Encrypted-
  boot skips (pre-issue-07) show as SKIP, not FAIL.

## Acceptance criteria

- [x] The guard's `max_parallel` math is correct across representative
      (MemAvailable, reserve) inputs and clamps to the configured cap.
- [x] Missing `/dev/kvm`, `libvirtd` down, or insufficient disk aborts with a
      clear reason before any VM starts.
- [x] The per-launch gate blocks a spawn when free RAM is below the threshold
      and proceeds once a cell finishes (unit-testable via the predicate).
- [x] `--smoke` runs only the pinned seeds; `--full` runs the whole pairwise set.
- [x] A failing cell does not abort the run; the summary shows all cells and the
      command exits non-zero on any FAIL.

## Blocked by

- `.scratch/combination-matrix/issues/05-vm-profile-synthesizer-oracle-dispatch.md`
