# 02 — Multi-disk topologies + reject none/independent

Status: done

## Parent

`.scratch/standalone-data-pools/PRD.md` (ADR 0027).

## What to build

Extend Standalone Data Pools to multi-disk vdevs so a single pool can be
redundant, and reject the topologies that make no sense for a standalone
pool.

Scope:

- Support `topology` values `mirror`, `raidz1`, `raidz2` (plus the
  already-working `stripe`) for `data_pools[]` entries: build the vdev
  spec from topology + the entry's partitions and create one pool
  spanning all its disks.
- Topology-vs-disk-count validation in the multi adapter's
  `layout_validate` (pure check, per ADR 0014): `mirror` ≥2, `raidz1`
  ≥2, `raidz2` ≥3 — a topology needing more disks than listed aborts.
- Reject `none` and `independent` for `data_pools` with a guiding error
  that points to `stripe` (one pool, no redundancy) or multiple entries
  (separate pools). Rationale: `build_vdev_spec` maps `none` to "first
  disk only", silently dropping the rest.

## Acceptance criteria

- [x] A `data_pools[]` entry with `topology: "mirror"` and two disks
      creates a mirrored pool; `raidz1`/`raidz2` create the matching
      raidz pool across their disks. (`build_vdev_spec` +
      `create_data_pools` already pass the topology through; unit-covered
      by `zfs-pools.bats`. Real `zpool` exercise is the VM smoke in 06.)
- [x] The `<name>/data` dataset mounts correctly for multi-disk pools.
      (Existing `create_data_pools` path; real mount asserted by 06.)
- [x] `mirror` with one disk (and the other under-count cases) aborts at
      validation with a clear message.
- [x] `none` and `independent` abort at validation with the guiding
      error (no disks are touched).
- [x] Unit tests cover the topology-count and none/independent rejection
      cases (prior art: `tests/layout-multi.bats`) and multi-disk vdev
      spec construction (prior art: `tests/zfs-pools.bats`).

## Blocked by

- 01 — Declarative standalone data pool (single-disk, end-to-end)

## Comments

- Done (TDD). Key finding: multi-disk vdev *construction* already worked
  — `build_vdev_spec` handles `mirror`/`raidz1`/`raidz2` and
  `create_data_pools` passes topology straight through. The only new code
  was **validation**: `layout_validate` previously ignored `data_pools[]`.
  - New pure helper `_zfs_validate_pool_topology <topo> <count>` in
    `lib/zfs-pools.sh` (sits with `build_vdev_spec`): silent+0 when valid,
    prints a reason+1 when not. `stripe`≥1, `mirror`≥2, `raidz1`≥2,
    `raidz2`≥3; `none`/`independent` rejected with a guiding message
    (→ `stripe` or multiple `data_pools[]` entries); anything else
    (incl. `raidz3`) → "unknown topology".
  - `layout_validate` gains a `data_pools[]` loop (inline `jq`, matching
    the `storage_groups` style) that `error`s as
    `Data pool '<name>': <reason>`. Pure check in the `validate` phase —
    no disk touched (ADR 0014/0016).
  - Tests: 5 `layout-multi.bats` cases (mirror×1, raidz2×2,
    none, independent, valid-pass) + 9 `zfs-pools.bats` helper cases
    (each ok/rejection class). Full suite 746 green, shellcheck clean.
  - Unblocks 04 and 06.
