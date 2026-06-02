# 04 — Unequal-disk size warning

Status: done

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

- [x] A `mirror`/`raidz` data pool over disks of different sizes prints
      a warning naming the pool, disks, sizes, and the smallest-disk
      cap, then continues (non-fatal).
- [x] No warning for `stripe`, single-disk pools, or equal-size
      redundant pools.
- [x] Unit test covers the size-check decision (true/false cases)
      (prior art: `tests/install-config.bats` / `tests/zfs-pools.bats`).

## Blocked by

- 02 — Multi-disk topologies + reject none/independent

## Comments

- Done (TDD).
  - Pure decision `_zfs_redundant_size_mismatch <topo> <size…>`
    (`lib/zfs-pools.sh`): returns 0 (warn) iff topology is redundant
    (`mirror`/`raidz1`/`raidz2`/`raidz3`) AND ≥2 sizes AND not all equal;
    else 1. 6 `zfs-pools.bats` cases (mirror unequal/equal, stripe
    unequal, single disk, raidz1 unequal, raidz2 equal).
  - Wired into `resolve_data_pools` (plan step): reads each disk's bytes
    (`lsblk -bdno SIZE`, drives the decision) + human size (`-dno`, for
    the message); on a mismatch, `warn`s naming the pool, topology, each
    disk + size, and the smallest-member cap. Non-fatal. 2 emission
    integration tests via a stubbed `lsblk` (warns on unequal mirror;
    silent on equal mirror).
- Folded in (operator decision) PRD story 15 — **data-pool disk
  existence**, which no prior slice validated:
  - New `_layout_disk_exists` seam (`lib/layout-multi.sh`) over the
    block-device test, so existence checks are overridable in fake-disk
    unit tests. `layout_validate`'s os/storage/data checks now all route
    through it. Data-pool disks checked last (so name/topology/mount
    errors surface first); a missing disk aborts before any destructive
    op. New "disk not found" test; the two fake-disk pass-tests stub the
    seam.
- Full suite 776 green, shellcheck clean. Unblocks nothing new (06 was
  already unblocked by 02+03); leaves only 05 (interactive) and 06 (VM).
