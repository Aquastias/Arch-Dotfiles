# 03 — Pool-name + uniqueness + mount validation

Status: done

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

- [x] An invalid name (leading digit, illegal char like `.`, reserved
      word `mirror`/`raidz1`, `cN` prefix) aborts with a clear message;
      `tank0` and `tank-photos` pass.
- [x] A duplicate pool name across rpool/dpool/data_pools aborts.
- [x] A disk used in more than one place (OS pool / storage group /
      another data pool) aborts.
- [x] Two pools with the same mountpoint abort; a mount equal to a
      reserved path (e.g. `/home`, `/boot/efi`) aborts.
- [x] Nested mounts (`/data` and `/data/tank0`) are accepted.
- [x] Validation runs before any destructive operation (all checks run
      in the `validate` phase, ADR 0016).
- [x] Unit tests cover `_zfs_valid_pool_name` (valid + each rejection
      class) and the validate rules (prior art:
      `tests/zfs-pools.bats`, `tests/layout-multi.bats`).

## Blocked by

- 01 — Declarative standalone data pool (single-disk, end-to-end)

## Comments

- Done (TDD). Two new pure helpers + cross-cutting guards in
  `layout_validate` (ADR 0014), all in the `validate` phase before any
  disk op.
  - `_zfs_valid_pool_name <name>` (`lib/zfs-pools.sh`): silent+0 ok /
    reason+1 bad. Enforces `^[A-Za-z][A-Za-z0-9_-]*$`, rejects `cN`
    prefix and reserved ZFS words (`mirror`, `raidz{,1,2,3}`, `draid*`,
    `spare`, `log`, `cache`, `special`, `dedup`). Applied to
    `data_pools[].name` only (os/storage names retrofit out of scope).
  - `_mount_is_reserved <path>` (`lib/layout-multi.sh`): 0 when the path
    shadows an OS dataset — `/`, `/home`, `/tmp`, `/persist`, or the
    `/var{,/*}` / `/boot{,/*}` **subtrees** (subtree, not bare prefix, so
    `/data` is free and `/variable` is not reserved).
  - `layout_validate` (gated on `data_pools[]` present, so existing multi
    configs are untouched): per-entry name format; pool-name uniqueness
    across `{rpool, dpool, data_pools…}`; disk reuse across os/storage/
    data (`sort|uniq -d`); mount rules over all declared storage mounts —
    reserved-path reject + exact-duplicate reject, nested mounts allowed.
  - Tests: 7 `_zfs_valid_pool_name` + 6 `_mount_is_reserved` unit cases;
    8 `layout_validate` integration cases (bad name, dup name, name==
    rpool, disk reuse ×2, reserved mount, dup mount, nested-pass). Full
    suite 767 green, shellcheck clean.
  - Unblocks 05 (interactive own-pool reuses both helpers) and 06.
