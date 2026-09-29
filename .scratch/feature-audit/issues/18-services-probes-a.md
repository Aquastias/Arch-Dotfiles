# 18: Services probes A (emulated hardware)

**What to build:** probes for borg (backup + restore), zfs-auto-snapshot,
tuned / power-profiles-daemon, cups (test print to a host
`ippeveprinter`), suspend/resume + hibernate (`virsh dompmsuspend`),
smartmontools (SATA disk), fwupd (devices + refresh).

**Blocked by:** 03, 09

**Status:** done

- [x] Host `ippeveprinter` started/stopped by the run
- [x] Suspend/resume proven; hibernate proven or `unverifiable` + reason
- [x] One probe per program; real run passes or yields Findings
