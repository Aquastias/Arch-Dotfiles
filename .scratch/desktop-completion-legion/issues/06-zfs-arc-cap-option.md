# 06: ZFS ARC cap option

**What to build:** a profile can cap ZFS ARC; the laptop caps it at 4 GiB so
games keep their memory. Unset means the ZFS default; the desktop stays
uncapped. No Guided Installer row. Parent: PRD (ADR 0161).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] New profile-only schema option `options.zfs.arc_max`, default empty.
- [x] Set: the ZFS modprobe config carries `zfs_arc_max` in bytes
      (size suffix such as `4G` converted).
- [x] Unset: nothing written.
- [x] Invalid value rejected by validation.
- [x] Laptop profile sets `4G`.
- [x] ZFS chroot bats cover set/unset; both Fleet Golden fixtures
      regenerated.
- [x] Arch Wiki (ZFS, ARC) fetched and cited.

## Comments

- 2026-11-01: the Arch Wiki (ZFS, ARC) sets the cap as the
  `zfs.zfs_arc_max=<bytes>` kernel parameter, so it ships as an
  installer-owned boot fragment every Bootloader Adapter appends (like zswap)
  rather than a modprobe.d file; ADR 0161 amended. Validation also rejects a
  cap on a non-ZFS root.
