# ADR 0030: Boot-time ZFS import strategy

## Status
Accepted

## Context
On a ZFS-root system the initramfs `zfs` hook imports the root pool by
scanning `/dev/disk/by-id` (`zfs_import_dir`), and the archzfs late hook
imports the remaining **cached** pools. Post-switch-root, the installer
enables `zfs-import-cache.service` and `zfs-import-scan.service`.

Two boot stalls were observed on a multi-disk machine with a slow
spinning HDD, intermittently and at *both* "settle every uevent"
barriers:

- **`:: Triggering uevents...`** — the initramfs `udev` hook runs a bare
  `udevadm settle` (120 s default); a slow-coldplugging device blocks it.
- **"A start job is running for udev-settle"** — `zfs-import-cache.service`
  hard-`Requires=systemd-udev-settle.service`, a unit systemd itself
  **deprecates**. When it stalls or times out, the import job fails with
  `Dependency failed` and boot is delayed.

The key observation: the post-boot import services are *redundant for
already-cached pools* — the initramfs already performed the real import
— yet they are what drags the deprecated `systemd-udev-settle` into the
boot path. Their value is narrow: a fallback for a pool that exists but
is not yet in the cache (e.g. one created after install).

## Decision
Treat the **initramfs as the authoritative importer** (root + every
cached pool, by stable by-id paths per ADR 0028), and make the post-boot
services a non-blocking safety net:

1. **Decouple the import services from `systemd-udev-settle`.** Ship FULL
   replacement units for `zfs-import-cache.service` and
   `zfs-import-scan.service` at `/etc/systemd/system/`, derived from the
   package's own `/usr/lib` units with the
   `Requires=`/`After=systemd-udev-settle.service` token filtered out —
   matching OpenZFS upstream's own removal. They remain `oneshot`,
   best-effort, and never gate boot. (A `Requires=` *reset drop-in* was
   tried first but does NOT remove a main-file dependency on systemd 260 —
   verified on a booted install; a full `/etc` unit wholly shadows the
   `/usr/lib` one with no merge, so the settle dep is simply absent.)
2. **Bound the initramfs settle.** Override `/etc/initcpio/hooks/udev`
   (which takes precedence over `/usr/lib/initcpio/hooks/udev`) so the
   hook runs the same `udevadm trigger` pair followed by
   `udevadm settle --timeout=30` instead of the unbounded default. Safe
   because the root pool is found by the by-id scan and the archzfs `zfs`
   hook retries the import, so a 30 s cap does not break a
   reasonably-fast root disk; it converts a multi-minute hang into a
   bounded wait.

## Considered alternatives
- **Migrate to a systemd-based initramfs (`systemd` hook).** Eliminates
  the global settle at both stages and is the modern path, but reworks
  the archzfs `zfs` hook integration, the encryption passphrase prompt,
  and the impermanence `zfs-rollback` hook (all written for the
  busybox/udev initramfs). Too invasive for a stall that clears itself.
- **Raise/keep the timeouts and leave `systemd-udev-settle` in place.**
  Keeps the deprecated barrier and the intermittent hang.
- **Drop the post-boot import services entirely.** Loses the fallback
  for a pool that is not yet in the cache, so a pool created after
  install would never auto-import.

## Consequences
- Boot no longer blocks on `systemd-udev-settle`; the "start job" stall
  is gone and the initramfs settle is capped at 30 s.
- Pools auto-import primarily via the initramfs cache, which is only
  reliable because ADR 0028 records stable by-id paths — this ADR
  depends on that one.
- The post-boot `zfs-import-*` services are best-effort and non-fatal; a
  failure there no longer means a pool is unavailable (the initramfs
  already imported it).
- We own a copy of the `udev` initramfs hook. A future maintainer must
  know it shadows the stock hook; it is kept minimal (same trigger,
  bounded settle) so it rarely needs syncing.
