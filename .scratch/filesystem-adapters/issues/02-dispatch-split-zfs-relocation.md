# 02 — Filesystem-keyed dispatch split + relocate ZFS into lib/layout/zfs/

Status: done
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

- [x] `root_adapter_source` / `data_formatter_source` return the ZFS adapter
      paths (`lib/layout/zfs/<mode>.sh`, `lib/layout/zfs/multi.sh`); an unbuilt
      filesystem errors (ADR 0043). `data_formatter_source zfs` points at
      `multi.sh` where `create_data_pools` lives (no premature extraction).
- [x] ZFS layout files (single/multi/common/plan) live under `lib/layout/zfs/`
      via `git mv`; internal BASH_SOURCE-relative sources move together and still
      resolve. Layout files are not chroot-staged, so no flat-copy lockstep.
- [~] The existing ZFS install path behaves identically (single + multi) — proven
      by the full bats gate (935, 0 fail incl. layout/zfs/profiles/chroot);
      live-VM smoke still unverified (no tty/fzf) but no install-path logic
      changed (pure relocation + `root_adapter_source` rename in 03-install.sh).
- [x] dispatch.bats rewritten for both seams + the unbuilt-fs error; all
      layout/dispatch bats pass; audit.sh updated to the zfs/ paths (PASS).

Status: done — dispatch.bats (6 tests) RED→GREEN; `git mv` relocation;
03-install.sh calls `root_adapter_source`; full gate 935/0. The one audit FAIL
(`extras.sh`) is pre-existing (fails identically on HEAD). VM smoke is the only
remaining unverified item.

## Blocked by

- None - can start immediately
