# 02 — Multi-disk topologies + reject none/independent

Status: ready-for-agent

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

- [ ] A `data_pools[]` entry with `topology: "mirror"` and two disks
      creates a mirrored pool; `raidz1`/`raidz2` create the matching
      raidz pool across their disks.
- [ ] The `<name>/data` dataset mounts correctly for multi-disk pools.
- [ ] `mirror` with one disk (and the other under-count cases) aborts at
      validation with a clear message.
- [ ] `none` and `independent` abort at validation with the guiding
      error (no disks are touched).
- [ ] Unit tests cover the topology-count and none/independent rejection
      cases (prior art: `tests/layout-multi.bats`) and multi-disk vdev
      spec construction (prior art: `tests/zfs-pools.bats`).

## Blocked by

- 01 — Declarative standalone data pool (single-disk, end-to-end)
