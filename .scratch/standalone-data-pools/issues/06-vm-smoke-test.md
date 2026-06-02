# 06 — VM smoke test: multi data pools

Status: ready-for-agent

## Parent

`.scratch/standalone-data-pools/PRD.md` (ADR 0027).

## What to build

A VM smoke test that exercises the real `zpool`/`sgdisk` paths unit
tests can't, covering Standalone Data Pools end-to-end on a booted
system. Sibling of `tests/vm/testing-multi-os-none.sh`.

Scope:

- New `tests/vm/testing-multi-data-pools.sh`: one OS disk plus a
  declarative `data_pools[]` config with one single-disk `stripe` pool
  and one two-disk `mirror` pool.
- Assert: install completes; the machine boots; rpool and both
  standalone pools import on first boot; each pool's `<name>/data`
  dataset is mounted at its mountpoint.
- Follow the existing VM harness conventions (committed test script +
  fixtures as used by the other `testing-multi-*.sh` scripts).

## Acceptance criteria

- [ ] `testing-multi-data-pools.sh` provisions 1 OS disk + a single-disk
      pool + a mirror pool and runs the installer to completion.
- [ ] After reboot, all pools import without `-f` and the `<name>/data`
      datasets are mounted at their configured mountpoints.
- [ ] The test fails loudly if any pool is missing or unmounted.
- [ ] Conforms to the existing VM test harness (prior art:
      `tests/vm/testing-multi-os-none.sh`).

## Blocked by

- 02 — Multi-disk topologies + reject none/independent
- 03 — Pool-name + uniqueness + mount validation
