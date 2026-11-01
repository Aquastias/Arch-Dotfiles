# 13: Desktop Audit Run

**What to build:** one desktop-variant Audit Run in the VM proves every
VM-verifiable change together: the niri autostart leak gone, pcmanfm-qt
owning FileManager1, kwallet behind niri's Secret portal, oomd monitoring,
the new packages present, blueman absent. Parent: PRD.

**Blocked by:** 07, 08, 09, 10, 11, 12.

**Status:** ready-for-agent

- [ ] One VM at a time (ADR 0155); `vm-agent.sh status` first, `stop`
      after.
- [ ] Every new probe passes in its sessions.
- [ ] No new findings beyond accepted Known Noise.
- [ ] Result recorded like prior Audit Run docs.
