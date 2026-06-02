# 04 — Unequal-disk size warning

Status: ready-for-agent

## Parent

`.scratch/standalone-data-pools/PRD.md` (ADR 0027).

## What to build

A non-fatal warning when a Standalone Data Pool uses a redundant
topology (`mirror`/`raidz1`/`raidz2`) across disks of differing sizes,
because ZFS caps usable space to the smallest member. Emitted at plan
time (not in `layout_validate` — it is a warning, not a gate).

Scope:

- A pure decision: given a vdev's disk sizes and topology, return
  whether to warn (redundant topology AND sizes differ). Returns false
  for `stripe`, single-disk pools, and equal-size redundant pools.
- Wire it into the data-pool plan step: when true, `warn` naming the
  pool, the disks and their sizes, and the usable cap.

## Acceptance criteria

- [ ] A `mirror`/`raidz` data pool over disks of different sizes prints
      a warning naming the pool, disks, sizes, and the smallest-disk
      cap, then continues (non-fatal).
- [ ] No warning for `stripe`, single-disk pools, or equal-size
      redundant pools.
- [ ] Unit test covers the size-check decision (true/false cases)
      (prior art: `tests/install-config.bats` / `tests/zfs-pools.bats`).

## Blocked by

- 02 — Multi-disk topologies + reject none/independent
