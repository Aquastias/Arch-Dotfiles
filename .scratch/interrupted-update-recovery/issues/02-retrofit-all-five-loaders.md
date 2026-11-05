# 02: Prefactor: retrofit tool recognises all five loaders

Status: ready-for-agent

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** the boot-hardening retrofit tool detects every
ESP-mirroring loader (systemd-boot, grub, efistub, limine, refind) on a
running system and installs the existing hardened ESP Kernel Sync and
Stray Kernel warn hook on each. GRUB is treated as ESP-mirroring, not
native-ZFS. Later slices add their artifacts to this one install path.

**Blocked by:** None (can start immediately).

- [ ] Detection correct for all five loaders against fake roots
- [ ] Unknown loader: clear error, no changes
- [ ] Idempotent; dry-run previews without writing
- [ ] Existing harden-boot bats suite extended and green
