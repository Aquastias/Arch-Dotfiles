Status: done

# Bats parallelism via GNU parallel

## Parent

`.scratch/tests-and-commons-cleanup/PRD.md`

## What to build

Make `.os/tests/run.sh` execute the bats suite in parallel using
`bats --jobs "$(nproc)"`. The bats `--jobs` flag requires GNU
`parallel`; the runner must hard-fail with a clear install hint when
`parallel` is absent, mirroring how the script already auto-vendors
bats-core on first run.

Tests are already `mktemp -d`-isolated, so within-file and
across-file parallelism are both safe.

Baseline measured 2026-05-23: 531 tests, ~57s sequential on a
24-core host. Expected after this slice: ~3–5s.

## Acceptance criteria

- [x] `run.sh` aborts with a non-zero exit and a `sudo pacman -S
      parallel` hint when `parallel` is missing from `$PATH`
- [x] When `parallel` is present, `run.sh` invokes
      `bats --jobs "$(nproc)" "$HERE"/*.bats`
- [x] All 531 tests still pass under parallel execution
- [x] Re-measure total wall time and record the result as a comment
      on this issue (used as the gate for issue 05)
- [x] No test files are modified by this slice

## Blocked by

None - can start immediately

## Comments

### 2026-05-24 — measurement

Landed in 4d13d60 (`run.sh` --jobs) + e701dde (`parallel` added to
core packages). Re-measured on same 24-core host:

- Full suite: 562 tests, **10.7s** wall (vs 57s baseline — 5.3× faster)
- `chroot-impermanence.bats` alone: **4.83s** wall (vs 30.6s seq)

The 4.83s figure is the gate input for issue 05 (threshold ~5s).
