# 03 — Pool-name + uniqueness + mount validation

Status: ready-for-agent

## Parent

`.scratch/standalone-data-pools/PRD.md` (ADR 0027).

## What to build

Config guardrails for `data_pools[]` so a bad config aborts early with a
clear message instead of a cryptic `zpool create` failure or a
boot-breaking shadowed mount. All checks live in the multi adapter's
`layout_validate` (pure check, per ADR 0014).

Scope:

- New pure helper `_zfs_valid_pool_name` (in the ZFS pools module):
  enforce `^[a-zA-Z][a-zA-Z0-9_-]*$`; reject ZFS reserved vdev words
  (`mirror`, `raidz1`/`raidz2`/`raidz3`, `draid*`, `spare`, `log`,
  `cache`, `special`, `dedup`) and `cN` prefixes. Returns ok or a
  reason. (Retrofitting onto `os_pool_name`/`storage_pool_name` is out
  of scope.)
- Name uniqueness across rpool + dpool + all `data_pools[]` names.
- Disk-reuse rejection: no disk appears in more than one of OS pool,
  storage groups, or data pools.
- Mount validation: fatal on an exact-duplicate mountpoint across all
  declared storage mounts, or a mount equal to an OS/reserved path
  (`/`, `/home`, `/var*`, `/boot*`, `/tmp`, `/persist`). Nested mounts
  (`/data` + `/data/tank0`) are allowed.

## Acceptance criteria

- [ ] An invalid name (leading digit, illegal char like `.`, reserved
      word `mirror`/`raidz1`, `cN` prefix) aborts with a clear message;
      `tank0` and `tank-photos` pass.
- [ ] A duplicate pool name across rpool/dpool/data_pools aborts.
- [ ] A disk used in more than one place (OS pool / storage group /
      another data pool) aborts.
- [ ] Two pools with the same mountpoint abort; a mount equal to a
      reserved path (e.g. `/home`, `/boot/efi`) aborts.
- [ ] Nested mounts (`/data` and `/data/tank0`) are accepted.
- [ ] Validation runs before any destructive operation.
- [ ] Unit tests cover `_zfs_valid_pool_name` (valid + each rejection
      class) and the validate rules (prior art:
      `tests/zfs-pools.bats`, `tests/layout-multi.bats`).

## Blocked by

- 01 — Declarative standalone data pool (single-disk, end-to-end)
