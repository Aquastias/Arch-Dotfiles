# cronie as universal infrastructure

Status: ready-for-agent

## Parent

`.scratch/host-package-cleanup/PRD.md`

## What to build

Reclassify cron as universal infrastructure per ADR 0026: its package
lives in the Base Package List and its service is enabled by the Chroot
Configuration Module, exactly like NetworkManager/resolved/timesyncd —
not as a bare Host Config package (which is never enabled today, so cron
is silently dead on every host) and not as a System Program (cron is
infrastructure, not an optional feature).

Add `cronie` to the Base Package List in `collect_packages`, and enable
`cronie.service` in the Chroot Configuration Module alongside the existing
base-daemon enables. This slice is code-only — it does not edit any Host
Config (the duplicate `cronie` entries are removed in the dedup slice).

## Acceptance criteria

- [ ] `collect_packages` output includes `cronie`.
- [ ] The collected list remains sorted and deduplicated.
- [ ] The Chroot Configuration Module enables `cronie.service` (no
      `systemctl start`).
- [ ] `packages.bats` asserts `cronie` is in the collected base set.
- [ ] `chroot-configure.bats` asserts `cronie.service` is enabled
      alongside NetworkManager/resolved/timesyncd.

## Blocked by

None - can start immediately.
