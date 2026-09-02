# 05 — Broken-installed-system serial + `--rescue`/`--reattach-iso`

**What to build:** A system that installed but won't boot is no longer a dead
end. The persistent flow appends `console=ttyS0,115200` to the installed
system's systemd-boot **and** GRUB loader entries, so a broken boot's kernel
output and LUKS-unlock prompt land on serial instead of being silent (reusing
the mechanism the boot-verify path already has). A new `--rescue` /
`--reattach-iso` path re-inserts the install ISO so the next boot lands on the
live ISO — with the autologin serial + SSH channels from ticket 01 — from which
a half-installed pool can be `zpool import`ed and inspected. A booted-but-broken
installed system keeps its harness SSH key (already true).

Anchored by ADR 0099.

**Blocked by:** 01 — rescue boots back into the live-ISO channels seeded there.

**Status:** ready-for-agent

- [ ] Persistent-flow installed systemd-boot and GRUB entries carry
      `console=ttyS0,115200`.
- [ ] `--rescue` / `--reattach-iso` re-inserts the install ISO so the next boot
      lands on the live ISO with ticket-01's channels.
- [ ] From a rescued live ISO the half-installed pool is importable for
      inspection.
- [ ] A booted-but-broken installed system remains SSH-reachable via the harness
      key (unchanged).
- [ ] Seam-1 test: installed loader entries (systemd-boot + GRUB) carry
      `console=ttyS0,115200` for the persistent flow.
- [ ] Seam-4 test (mocked libvirt): `--rescue` re-attaches the ISO.
