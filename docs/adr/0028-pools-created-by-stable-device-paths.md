# ADR 0028: Create pools by stable device paths, not /dev/sdX

## Status
Accepted

## Context
A multi-disk install with Standalone Data Pools (ADR 0027) booted with
the OS up but a data pool missing. The initramfs reported:

```
:: running hook [zfs]        ZFS: importing pool rpool.
:: running late hook [zfs]   ZFS: importing pool 'tank0'.
cannot import 'tank0': one or more devices is currently unavailable
```

Root cause: pools were created with bare kernel device names. The
config's `data_pools[].disks` hold `/dev/sdb`; `part_name` turns that
into `/dev/sdb1`; `zpool create … /dev/sdb1` records `/dev/sdb1` in the
vdev label **and** in the seeded `/etc/zfs/zpool.cache`
(`_chroot_seed_zpool_cache`). The kernel assigns `/dev/sdX` by
disk-enumeration order, which is **not stable** across reboots on a
machine with multiple disks of differing sizes/controllers. After a
reorder, the cached `/dev/sdb1` points at a different disk → import
fails.

Why the root pool survived: the initramfs imports `rpool` by *scanning*
`/dev/disk/by-id` (`zfs_import_dir=/dev/disk/by-id`), which is immune to
renaming. Data pools, by contrast, are imported from the cache (the
archzfs late hook, then post-boot `zfs-import-cache.service`), which
carries the stale `/dev/sdX`. The failure persists after boot because
upstream skips `zfs-import-scan.service` (the by-scan fallback that
*would* find the pool) whenever a non-empty `zpool.cache` exists.

ADR 0027 assumed "boot-time import of N pools needs no change" because
the cache already loops over every pool. That held only because the
existing VM smoke test used four **identical** disks, where `/dev/sdX`
happens to be stable — false confidence. The reporting hardware had
disks of various sizes.

## Decision
Create every pool using a **stable device path**, never a bare
`/dev/sdX`. A single choke point translates device tokens just before
`zpool create`, since both single- and multi-disk layouts route through
`_zpool_create`:

- `_zfs_stable_part_path` resolves a partition node to a stable symlink
  that points at it. Tier 1 `/dev/disk/by-id` (matches the existing
  `zfs_import_dir` convention; prefers a non-`wwn` id for readability).
  Tier 2 `/dev/disk/by-partuuid` (always present for GPT partitions,
  fully stable — covers disks/VMs that expose no usable by-id). Falls
  back to the input unchanged when nothing maps (loop/zram, test host).
- `_zpool_translate_vdev` maps each device token in a vdev spec while
  passing topology keywords (`mirror`/`raidz…`/`log`/`cache`/…) through.
- `_zpool_create` runs `udevadm settle` then translates `vdev_spec`
  before invoking `zpool create`, so the label + cache record the stable
  path. The root-pool scan import and the data-pool cache import then
  both survive enumeration changes.

ZFS records whatever path it is given at create time; giving it a stable
path is sufficient — no export/re-import dance, no `zpool.cache`
post-processing.

## Considered alternatives
- **Re-import pools with `-d /dev/disk/by-id` before seeding the
  cache.** Rejected: the cache is seeded and baked into the initramfs
  *inside* the chroot, before `finalize` exports anything, and `rpool`
  is mounted there (cannot be exported), so a re-import pass cannot run
  early enough to fix the initramfs cache.
- **Drop data pools from the initramfs cache; import them only
  post-boot.** Rejected: needs two divergent caches (root-only in the
  initramfs, full in the real root) and still leaves post-boot
  `zfs-import-cache` reading stale `/dev/sdX`. Stable paths fix every
  consumer at once.
- **Make `part_name` itself return by-id.** Rejected: `part_name` is a
  pure string helper reused by fstab/ESP code that wants kernel names;
  overloading it couples unrelated call sites.

## Consequences
- Pool vdev labels and `zpool.cache` now hold `/dev/disk/by-id` or
  `/dev/disk/by-partuuid` paths. `zpool status` shows stable paths.
- Regression guards: the multi-data-pools VM smoke test now asserts
  every leaf vdev resolves via a stable path (`VM_VERIFY_BYID`), and a
  new `testing-multi-data-pools-reorder.sh` permutes the data disks
  between install and boot (`VM_REORDER_BOOT_DISKS`) to reproduce the
  exact enumeration-reorder failure. The pure helpers and the reorder
  transform are unit-covered (`zfs-pools.bats`, `vm-pool-verify.bats`,
  `vm-reorder-disks.bats`).
- No config or schema change: `data_pools[].disks` may still be written
  as `/dev/sdX`; the translation happens at create time.
