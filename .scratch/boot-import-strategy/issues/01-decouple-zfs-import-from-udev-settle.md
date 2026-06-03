# Decouple zfs-import services from systemd-udev-settle

Status: ready-for-agent

## Parent

`.scratch/boot-import-strategy/PRD.md`

## What to build

Ship systemd drop-ins, written by the Chroot Configuration Module's ZFS
step, that remove the dependency on the deprecated `systemd-udev-settle`
from both the cache-import and scan-import ZFS services. They remain
oneshot, best-effort, and no longer gate boot, so a slow or stalled udev
settle can't fail pool imports or produce the "A start job is running
for systemd-udev-settle" stall in the booted system. The initramfs
remains the authoritative importer; these services are a non-blocking
fallback for a pool that is not yet in the cache.

## Acceptance criteria

- [ ] On a booted install, the ZFS import services no longer require
      `systemd-udev-settle`.
- [ ] Pools still import at boot (via the initramfs), and the post-boot
      services run without a failed dependency.
- [ ] A pure emitter produces the drop-in content; a unit test asserts
      the settle dependency is removed.
- [ ] No regression to existing chroot ZFS service configuration.

## Blocked by

None - can start immediately.
