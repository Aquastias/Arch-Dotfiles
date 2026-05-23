Status: ready-for-agent

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

- [ ] `run.sh` aborts with a non-zero exit and a `sudo pacman -S
      parallel` hint when `parallel` is missing from `$PATH`
- [ ] When `parallel` is present, `run.sh` invokes
      `bats --jobs "$(nproc)" "$HERE"/*.bats`
- [ ] All 531 tests still pass under parallel execution
- [ ] Re-measure total wall time and record the result as a comment
      on this issue (used as the gate for issue 05)
- [ ] No test files are modified by this slice

## Blocked by

None - can start immediately
