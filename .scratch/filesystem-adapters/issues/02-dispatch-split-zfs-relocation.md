# 02 — Filesystem-keyed dispatch split + relocate ZFS into lib/layout/zfs/

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

Generalize the layout dispatch into the two seams ADR 0043 defines, and relocate
the ZFS layout files into a `zfs/` subdirectory — all behavior-preserving for the
existing ZFS install path. The dispatch gains `root_adapter_source <fs> <mode>`
(selects the Root Layout Adapter that owns the OS disk) and
`data_formatter_source <fs>` (selects the Data Group Formatter for one group,
mode-independent). The current ZFS single/multi Layout Modules become the ZFS
Root Layout Adapter under `lib/layout/zfs/`; ZFS data-pool creation becomes the
ZFS Data Group Formatter. Unbuilt filesystems still error via the dispatch seam.

Mind the BASH_SOURCE root-sibling sourcing + chroot flat-copy lockstep hazard
when folding files into the subdirectory.

## Acceptance criteria

- [ ] `root_adapter_source` / `data_formatter_source` return the ZFS adapter
      paths; an unbuilt filesystem errors (referencing ADR 0043).
- [ ] ZFS layout files live under `lib/layout/zfs/`; all relative sourcing +
      chroot staging still resolves (no broken BASH_SOURCE paths).
- [ ] The existing ZFS VM smoke install path behaves identically (single + multi
      mode) — pure refactor.
- [ ] Existing layout/dispatch bats pass; dispatch tests extended for the two
      new seam functions and the unbuilt-fs error.

## Blocked by

- None - can start immediately
