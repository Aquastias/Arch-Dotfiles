Status: wontfix

# Config-test speed: source-once via `setup_file` + `export -f`

## Parent

`.scratch/installer-test-realism/PRD.md`

## Resolution (measured, de-scoped 2026-07-21)

De-scoped after measurement — the tests-only lever is both blocked and
low-value:

- `export -f` moves functions but **bash cannot export array constants**
  (`_MENU_FIELDS`, `_MENU_CATEGORIES`, `_CTL_DIVIDER`) across the process
  boundary, so a naive `setup_file` broke 10 guided-controller tests.
  Doing it correctly needs `declare -p` array-rehydration machinery shared
  across ~43 config files — far more than "source-once".
- `tests/run.sh` already passes `--jobs`, and bats parallelises
  **within-file** (guided-controller alone: 16s serial → 3.3s at
  `--jobs 24`). The per-file serial cost is already hidden in the full
  run; the only gain is reduced CPU ≈ **1-2s off the ~151s wall**, even
  done perfectly. The single-file dev-loop win (16s→9s) is real but
  narrow.
- The ~110-120s target is **not reachable tests-only**. It lives in the
  deferred lib `jq`-batching in `lib/config/{state,nav,edits,menu}.sh`
  (which also speeds the live guided TUI). Track that separately if the
  wall-time is ever a real pain.

## What to build

Cut the suite's wall-time long pole — the guided TUI config tests — with a
tests-only change (ADR 0048). Each `@test` currently re-sources 4-6
`lib/*.sh` in `setup()`; move those `source` lines into `setup_file` and
`export -f` the sourced functions so each test subshell sees them without
re-sourcing. Keep per-test mutable state (tmpdir, state/nav files) in
`setup()`. Dedupe redundant `run` invocations where one call can assert
several properties.

Apply to `guided-controller.bats` (~16 s, 115 tests), `guided-shell.bats`
(~15 s), `guided-menu.bats` (~10 s) first, then any other file where the
pattern pays. No production `lib/*.sh` change — `jq`-fork batching is a
deferred follow-up.

## Acceptance criteria

- [ ] Lib `source` moved to `setup_file` + `export -f` in the three target
      files; per-test mutable state stays in `setup()`
- [ ] Test behavior unchanged (same names/count, or a documented dedupe)
- [ ] Before/after suite wall-time recorded; soft target ~110-120 s on
      24 cores (record the number even if not hit)
- [ ] No production `lib/*.sh` change
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

None - can start immediately (independent of the validator slices).
