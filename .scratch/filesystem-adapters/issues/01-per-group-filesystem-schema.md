# 01 — Per-group filesystem/encryption schema + validation contract

Status: done
Type: AFK

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

Make a data group able to declare its own filesystem and encryption,
independently of the OS/root, as an additive schema change that does not alter
any existing ZFS install behavior. The top-level `filesystem` keeps its current
role (names the OS/root filesystem, drives `encryption_method` default +
impermanence eligibility). Each `storage_groups[]` / `data_pools[]` entry gains
an **optional** `filesystem` (defaults to the root value when absent) and an
**optional** `encryption` bool (independent of the root). The closed-schema
validator must accept these new optional keys and reject unknown ones as before.

Extend the validation contract so it enforces the filesystem rules from ADR
0043: topology is filesystem-conditional, and ext4/xfs are single-disk only.

Scope note: applies to **both** `data_pools[]` (Standalone Data Pools) and
`storage_groups[]`. The semantics of a *non-ZFS* storage group vs the single
Combined Data Pool is deferred to the layout slices (05/07) — this slice is
schema/accessor/validation only.

## Acceptance criteria

- [x] An existing ZFS Host Profile (no per-group `filesystem`/`encryption`)
      validates and assembles into an identical Effective Config — no behavior
      change. (full config + layout/profiles/zfs/chroot suites green)
- [x] A data group with `filesystem: ext4` (or `xfs`) and `disk_count > 1` is
      rejected by validation, naming the offending path.
- [x] A group with `filesystem: btrfs` accepts `raid0`/`raid1`/`raid10`; ZFS
      accepts `mirror`/`stripe`/`independent`/`raidz`/`raidz1`/`raidz2`/`none`;
      ext4/xfs accept `single` only.
- [x] A group with no `filesystem` resolves to the root filesystem via the
      accessor (data_pool + storage_group).
- [x] Per-group `encryption` round-trips a stored `false` correctly (explicit
      null check, not `// default`).
- [x] Impermanence remains rejected unless root `filesystem ∈ {zfs, btrfs}`
      (unchanged `_validation_filesystem`; regression-covered).
- [x] bats covers the validation contract (topology-per-fs, single-disk
      constraint, encryption-bool round-trip, accessor default-inheritance) +
      closed-schema acceptance of the new keys.

Status: done — `tests/config/validation-group-filesystem.bats` (23 tests) +
closed-schema test in `profile-loader.bats`; wired into
`validate_install_context`. Full suite green (config 584, layout/profiles/zfs/
chroot 349, 0 fail).

## Blocked by

- None - can start immediately
