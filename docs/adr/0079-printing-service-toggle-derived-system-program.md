# Printing service is a toggle-derived system program

`cups` used to be an unconditional Host Core `system_programs` entry — installed
on every host, surfacing only as an inherited row buried in the Guided
Installer's Packages → system-programs picker. We replace that with
**`options.printing.enabled`** (bool, default `true`, normalised-out when true):
its own root-level **Printing service** Configuration Category holding a single
[[Cycle Field]]. `cups` is dropped from Host Core and instead **injected into
the Effective Config's `system_programs` at assembly time** when the toggle is
on, so
the Runner installs it in the chroot exactly as before (its `install.sh` still
enables `cups.service`). This is the first **toggle-derived System Program** —
distinct from `options.ssh.enabled`, which only enables a service on a package
(`openssh`) that base pacstrap always installs; here the toggle gates the
*installation* itself, so cups is genuinely absent when off.

## Considered options

- **Exclusion-flip** (keep `cups` in Host Core, toggle off writes
  `system_programs_exclude`) — rejected: cheapest, but cups then shows in *two*
  places (the Printing toggle **and** the Packages picker), and models the
  default state as "always declared, sometimes excluded" — the exact muddled
  provenance the toggle is meant to remove.
- **Fold into General** — rejected: General is machine *identity* (hostname,
  timezone); a service-enablement switch is a twin of Security/Backup, so it
  earns its own category (single-field categories already exist — Bootloader,
  Kernels).
- **Put the key under `post_install.*`** — rejected: that namespace is the
  Primary-User paru pass for *User* Programs; cups is a root/chroot System
  Program, so `options.*` (home of `options.ssh.enabled`) is correct.
- **ssh-style enable-only** (add cups to base pacstrap, toggle just the service)
  — rejected: leaves cups installed when "off", failing the clean-removal goal.

## Consequences

- cups is **filtered from the Packages → system-programs picker** — the Printing
  toggle is its sole menu home. The picker special-cases the toggle-owned
  program so it never re-appears.
- The Package Resolver, which today reports **no** system programs at all, gains
  one derived entry: `options.printing.enabled: true` surfaces cups as
  `source=printing` / layer `derived` in the read-only `derived` section and
  `explain-packages`, giving it provenance parity with Security & Backup.
- The injection lives at Effective-Config assembly (the `--profile` and Guided
  Proceed/Export paths); the unattended `install.sh <config-file>` seam consumes
  a pre-assembled config, so its `system_programs` already carries cups when the
  authoring front-end enabled printing.
- `options.printing.enabled` becomes committed Host Profile surface: the closed
  schema allowlist + accessors must gain the key in lockstep.
