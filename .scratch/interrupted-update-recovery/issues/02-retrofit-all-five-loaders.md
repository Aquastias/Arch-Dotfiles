# 02: Prefactor: retrofit tool recognises all five loaders

Status: done

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** the boot-hardening retrofit tool detects every
ESP-mirroring loader (systemd-boot, grub, efistub, limine, refind) on a
running system and installs the existing hardened ESP Kernel Sync and
Stray Kernel warn hook on each. GRUB is treated as ESP-mirroring, not
native-ZFS. Later slices add their artifacts to this one install path.

**Blocked by:** None (can start immediately).

- [x] Detection correct for all five loaders against fake roots
- [x] Unknown loader: clear error, no changes
- [x] Idempotent; dry-run previews without writing
- [x] Existing harden-boot bats suite extended and green
