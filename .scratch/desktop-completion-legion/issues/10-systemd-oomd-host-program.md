# 10: systemd-oomd Host Program

**What to build:** fleet hosts kill a runaway app before the desktop
freezes: systemd-oomd watches swap exhaustion system-wide and memory
pressure in user sessions. Non-fleet installs are unchanged. Parent: PRD.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] New `system` Host Program per the program spec: enables
      `systemd-oomd.service`; ships drop-ins `-.slice` →
      `ManagedOOMSwap=kill`, `user@.service` →
      `ManagedOOMMemoryPressure=kill` + `ManagedOOMMemoryPressureLimit=50%`.
- [ ] Program spec cites `systemd-oomd(8)` / `systemd.resource-control(5)`
      and records that the Arch Wiki has no config section.
- [ ] Declared in the Fleet Layer `host_programs`.
- [ ] Program bats cover drop-in content and the service; both Fleet Golden
      fixtures regenerated.
- [ ] Feature Audit probe: `oomctl` lists both monitored units.
