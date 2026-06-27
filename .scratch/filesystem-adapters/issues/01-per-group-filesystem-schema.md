# 01 — Per-group filesystem/encryption schema + validation contract

Status: ready-for-agent
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

## Acceptance criteria

- [ ] An existing ZFS Host Profile (no per-group `filesystem`/`encryption`)
      validates and assembles into an identical Effective Config — no behavior
      change.
- [ ] A data group with `filesystem: ext4` (or `xfs`) and `disk_count > 1` is
      rejected by validation, naming the offending path.
- [ ] A data group with `filesystem: btrfs` accepts `single`/`raid0`/`raid1`/
      `raid10` topology; ZFS accepts `mirror`/`raidz1`/`raidz2`/`stripe`.
- [ ] A group with no `filesystem` resolves to the root filesystem via the
      accessor.
- [ ] Per-group `encryption` round-trips a stored `false` correctly (explicit
      null check, not `// default`).
- [ ] Impermanence remains rejected unless root `filesystem ∈ {zfs, btrfs}`.
- [ ] bats covers the validation contract (topology-per-fs, single-disk
      constraint, encryption-bool round-trip, accessor default-inheritance),
      mirroring existing `config/validation` tests.

## Blocked by

- None - can start immediately
