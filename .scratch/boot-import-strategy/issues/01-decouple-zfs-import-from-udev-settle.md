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
  Box 2 ticked (pools import + post-boot services clean). Box 1 ("no
  longer require settle") left open: indirect evidence strong (a Requires=
  on the deprecated unit would fail the dep — it didn't), but the direct
  proof is in-guest `systemctl show zfs-import-cache.service -p Requires`,
  which this host can't run (no zpool/sudo; ZFS only inside guests).
