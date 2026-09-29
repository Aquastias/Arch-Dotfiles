# 02: Tracer: base variant install + first boot

**What to build:** first real end-to-end Audit Run. New VM Host Profile
`arch-audit` (kde + niri + hyprland, Noctalia, SOPS Test Age Key,
impermanence, ZFS native encryption, 2-disk mirror + data pool, swap, every
security/backup/power option, every registry program). An Audit Manifest
with the base only. `feature-audit run` provisions it through the persistent
VM Harness flow, answers the encryption/age prompts, collects the installer
log and first-boot signals, runs `report`, and leaves raw logs in a
gitignored timestamped run folder. Adds VM Agent Control `pull`.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] `arch-audit` host passes the Profile Loader + harness validation
- [ ] Manifest (JSONC, tests VM tree) lists the base variant with ADRs
- [ ] `run` installs base unattended, one VM, host-capacity guard
- [ ] Collected: installer log (serial + on-disk), `systemctl --failed`
      system/user, journal ≥ warning system/user, coredumps, kernel
      errors — all tagged `install`/`boot1`
- [ ] `vm-agent pull` verb + pure-function bats
- [ ] Run folder gitignored; `run` ends with `report`, same exit rule
- [ ] One real run completes on the base and yields a findings list
