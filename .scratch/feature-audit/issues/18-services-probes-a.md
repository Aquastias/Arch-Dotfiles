# 18: Services probes A (emulated hardware)

**What to build:** probes for borg (backup + restore), zfs-auto-snapshot,
tuned / power-profiles-daemon, cups (test print to a host
`ippeveprinter`), suspend/resume + hibernate (`virsh dompmsuspend`),
smartmontools (SATA disk), fwupd (devices + refresh).

**Blocked by:** 03, 09

**Status:** ready-for-agent

- [ ] Host `ippeveprinter` started/stopped by the run
- [ ] Suspend/resume proven; hibernate proven or `unverifiable` + reason
- [ ] One probe per program; real run passes or yields Findings
