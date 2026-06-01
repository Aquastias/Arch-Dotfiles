# ADR 0026: Universal infra daemons live in the Base Package List, not System Programs

**Status:** Accepted.

## Context

Two ways exist to land a package whose daemon must be enabled at boot.
ADR 0021 made `cups` a System Program (`programs/office/cups/`) so its
service enablement lives "where service enablement actually lives." But
the truly universal daemons — `NetworkManager`, `systemd-resolved`,
`systemd-timesyncd`, the `zfs-*` units — were never Programs: their
packages are in the hardcoded Base Package List (`lib/packages.sh`) and
they are enabled directly in the Chroot Configuration Module
(`lib/chroot/configure.sh`). That second pattern was never written down,
so when `cronie` needed enabling there was no documented rule for which
pattern it follows — and the cups precedent invited making cron a
System Program too.

## Decision

A daemon **every** host needs running is universal infrastructure: its
package goes in the Base Package List and it is enabled in the Chroot
Configuration Module. A daemon only **some** hosts want is a feature: it
is a System Program with `system_services`, enabled by the Program
Runner. `cronie` is universal infrastructure — added to the Base Package
List and enabled in `configure.sh`, like NetworkManager.

The boundary test: **"does every host need this daemon running?"** Yes →
Base Package List + `configure.sh`. No → System Program.

## Considered alternatives

**cronie as a System Program (cups model).** Declarative and consistent
with 0021, but treats infrastructure as a selectable feature, needs a
new program category (no existing one fits cron), and would have every
host's `system_programs` redundantly list a daemon every host wants.

**cronie as a bare host package.** No service-enable seam in a Host
Package List, so cron installs but never runs — a silent break.

## Consequences

- cron, NetworkManager, resolved, timesyncd, and the zfs units share one
  documented home; none is a System Program.
- cups and sops remain the System Program pattern — both are optional
  features (printing, secrets), not universal infrastructure.
- A reader is steered away from "promoting" an infra daemon to a System
  Program for false consistency with cups.
