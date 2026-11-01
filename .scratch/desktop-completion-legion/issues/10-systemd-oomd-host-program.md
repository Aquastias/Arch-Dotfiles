# 10: systemd-oomd Host Program

**What to build:** fleet hosts kill a runaway app before the desktop
freezes: systemd-oomd watches swap exhaustion system-wide and memory
pressure in user sessions. Non-fleet installs are unchanged. Parent: PRD.

**Blocked by:** None (can start immediately).

**Status:** done

- [x] New `system` Host Program per the program spec: enables
      `systemd-oomd.service`; ships drop-ins `-.slice` →
      `ManagedOOMSwap=kill`, `user@.service` →
      `ManagedOOMMemoryPressure=kill` + `ManagedOOMMemoryPressureLimit=50%`.
- [x] Program spec cites `systemd-oomd(8)` / `systemd.resource-control(5)`
      and records that the Arch Wiki has no config section.
- [x] Declared in the Fleet Layer `host_programs`.
- [x] Program bats cover drop-in content and the service; both Fleet Golden
      fixtures regenerated.
- [x] Feature Audit probe: `oomctl` lists both monitored units.

## Comments

- 2026-11-02: the PRD's values (swap-kill on `-.slice`, 50% on
  `user@.service`) were stale memory. Fedora's current systemd-oomd-defaults
  (src.fedoraproject.org rpms/systemd) ship
  `oomd.conf.d/10-oomd-defaults.conf` (DefaultMemoryPressureDurationSec=20s)
  and `10-oomd-per-slice-defaults.conf` (ManagedOOMMemoryPressure=kill,
  Limit=80%) in `system.slice.d/` and the user `slice.d/`; mirrored at /etc
  admin paths. The probe checks `/system.slice` is monitored.
