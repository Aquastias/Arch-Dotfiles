# udisks-ignore rule for ZFS members

Status: done

## Parent

`.scratch/pool-owners-access/PRD.md`

## What to build

A udev rule, written by the Chroot Configuration Module on every
install, that marks any partition whose filesystem type is `zfs_member`
as ignored by udisks2. On the installed system this stops a udisks2
backed file manager (KDE Solid/Dolphin and friends) from listing ZFS
pool members as removable drives — which today prompt for a password and
then fail with "zfs_member not configured in kernel." The rule is
written unconditionally; it is a harmless no-op on a host without
udisks2 (servers).

## Acceptance criteria

- [ ] On a booted install, ZFS member partitions no longer appear as
      mountable devices in a udisks2-backed file manager.
- [ ] The rule is present regardless of whether a desktop environment
      was selected.
- [ ] A pure emitter produces the rule content; a unit test asserts it
      targets `zfs_member` and sets the ignore flag.
- [ ] No regression to existing chroot configuration.

## Blocked by

None - can start immediately.
