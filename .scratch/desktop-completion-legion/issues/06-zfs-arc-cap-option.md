# 06: ZFS ARC cap option

**What to build:** a profile can cap ZFS ARC; the laptop caps it at 4 GiB so
games keep their memory. Unset means the ZFS default; the desktop stays
uncapped. No Guided Installer row. Parent: PRD (ADR 0161).

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] New profile-only schema option `options.zfs.arc_max`, default empty.
- [ ] Set: the ZFS modprobe config carries `zfs_arc_max` in bytes
      (size suffix such as `4G` converted).
- [ ] Unset: nothing written.
- [ ] Invalid value rejected by validation.
- [ ] Laptop profile sets `4G`.
- [ ] ZFS chroot bats cover set/unset; both Fleet Golden fixtures
      regenerated.
- [ ] Arch Wiki (ZFS, ARC) fetched and cited.
