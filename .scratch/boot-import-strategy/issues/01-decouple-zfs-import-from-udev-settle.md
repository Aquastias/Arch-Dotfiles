# Decouple zfs-import services from systemd-udev-settle

Status: needs-info

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
- [x] Pools still import at boot (via the initramfs), and the post-boot
      services run without a failed dependency.
- [x] A pure emitter produces the drop-in content; a unit test asserts
      the settle dependency is removed.
- [x] No regression to existing chroot ZFS service configuration.

## Blocked by

None - can start immediately.

## Comments

- Implemented (TDD): `lib/chroot/zfs-import.sh` — pure emitter
  `zfs_import_settle_dropin` prints a `[Unit]` drop-in that resets
  `Requires=`/`After=` and re-adds only `After=cryptsetup.target` (drops
  the deprecated `systemd-udev-settle`); thin writer
  `zfs_import_write_settle_dropins <root>` drops it into both
  `zfs-import-cache.service.d/` and `zfs-import-scan.service.d/` as
  `10-no-udev-settle.conf`. Wired into `configure.sh` after the
  `systemctl enable zfs-import-*` block.
- 5 new `chroot-zfs-import.bats` cases (no settle, Requires reset,
  cryptsetup ordering kept, writer for each service). Full chroot bats
  green, `shellcheck -x -P SCRIPTDIR` clean.
- Unit ACs done. Remaining (boxes 1-2): a booted-install / VM run to
  confirm the services no longer require settle and pools still import —
  covered by the existing boot-verify VM smoke test, no libvirt on this
  dev host. Status stays `ready-for-agent` for a host that can run it.
- 2026-06-06: ran boot-verify on real KVM at HEAD (dirty-cache fixture,
  pinned 2026.05.01 ISO). `INSTALLER-EXIT-0` → `FIRSTBOOT-OK`. Boot log:
  initramfs imports rpool (`:: hook [udev]` → `[zfs]` → "Importing pool
  rpool"); post-boot "Import ZFS pools by cache file" Finished + "ZFS
  pool import target" Reached, NO failed dependency, NO settle stall.
  Box 2 ticked (pools import + post-boot services clean).
- 2026-06-06: Box 1 DISPROVEN. Added a test-only serial diagnostic dump to
  the boot-verify first-boot unit (seed-generator) running
  `systemctl show zfs-import-cache.service zfs-import-scan.service -p
  Requires -p After` on the BOOTED installed system. Result:
    Requires=system.slice systemd-udev-settle.service
    After=...cryptsetup.target...systemd-udev-settle.service
  BOTH services STILL require + order after `systemd-udev-settle.service`.
  The drop-in is loaded but ineffective.
- ROOT CAUSE (reproduced on this host, systemd 260, no VM): an empty
  `Requires=` / `After=` reset in a drop-in does NOT remove a dependency
  declared in the unit's main file. A probe unit `Requires=
  systemd-udev-settle.service dbus.service` + a `[Unit]\nRequires=` drop-in
  (confirmed loaded via `systemctl cat`) still showed BOTH deps after
  `daemon-reload`. So `zfs_import_settle_dropin`'s reset approach cannot
  decouple the services; its unit test only asserts the emitted TEXT, not
  the runtime effect — a shape-vs-behavior gap.
- FIX NEEDED (rework, not done here): drop-in reset is a dead end on
  systemd 260. Ship a FULL replacement unit at
  `/etc/systemd/system/zfs-import-{cache,scan}.service` (overrides the
  `/usr/lib` unit wholesale, omitting the settle Requires/After), or
  another mechanism, then re-verify with this same diagnostic. AC #1 stays
  unchecked; reopening. Status → `needs-info` (decide rework approach).
