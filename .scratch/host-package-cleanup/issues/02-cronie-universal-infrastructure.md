# cronie as universal infrastructure

Status: done

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

- [x] `collect_packages` output includes `cronie`.
- [x] The collected list remains sorted and deduplicated.
- [x] The Chroot Configuration Module enables `cronie.service` (no
      `systemctl start`).
- [x] `packages.bats` asserts `cronie` is in the collected base set.
- [x] `chroot-configure.bats` asserts `cronie.service` is enabled
      alongside NetworkManager/resolved/timesyncd.

## Blocked by

None - can start immediately.

## Comments

- Done (TDD). `cronie` added to the base array in `collect_packages`
  (`lib/packages.sh`). Service enable extracted into a sourceable helper
  `lib/chroot/base-services.sh::enable_base_services` (NetworkManager,
  systemd-resolved, systemd-timesyncd, cronie) so the set is testable;
  `configure.sh` now calls it instead of inline `systemctl enable` lines.
  The helper ships via the existing `cp -r lib/chroot` staging.
- Tests: +1 `packages.bats` (cronie in base), +2 `chroot-configure.bats`
  (stub systemctl → assert the four enables). Full bats suite green,
  shellcheck clean.
