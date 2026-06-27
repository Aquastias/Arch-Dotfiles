# Unified swap row + swapedit sub-editor (enabled + size)

Status: ready-for-agent

## Parent

`.scratch/swap-zswap-unified/PRD.md`

## What to build

Collapse the two **Disks** rows (`swap` toggle + `swap size`) into a single
**swap** row in the Guided Installer. Selecting it drills into a new `swapedit`
sub-screen following the data-pools editor convention. The sub-screen lets the
operator toggle swap on/off and set its size as free text (`auto` or e.g. `8G`).

This slice works entirely over the **existing** Config State keys
(`options.swap`, `options.swap_size`) — no schema change, no zswap yet. It is the
UI refactor that later slices build on.

Behavior:

- The Disks category shows one `swap` row (for every filesystem and single-disk
  layout); the separate `swap size` row is gone.
- Entering `swap` navigates to `swapedit`; `← Back` returns to the Disks
  category.
- swapedit rows: `enabled` (Enter toggles on/off); `size` (free-text editor,
  shown only when swap is on); `← Back`.
- The swap row's one-line value summarizes as `off` when swap is off, otherwise
  the size (e.g. `auto`, `8G`). (The zswap suffix is added in a later slice.)
- Edits flow through the existing Config State write + autocommit path, so
  undo/redo/reset already cover them.

## Acceptance criteria

- [ ] The Disks category renders exactly one swap row and no `swap size` row.
- [ ] The swap row appears for ZFS, ext4, and xfs, and on single-disk layouts.
- [ ] Entering the swap row navigates to the `swapedit` screen; back returns to
      the Disks category.
- [ ] `enabled` toggles `options.swap` true/false.
- [ ] `size` opens the free-text editor and saves to `options.swap_size`;
      `auto` and explicit sizes both round-trip.
- [ ] The `size` row is hidden when swap is off.
- [ ] The swap row summary renders `off` (swap off) or the size (swap on).
- [ ] Undo/redo/reset cover swap edits.
- [ ] Controller bats cover the above (prior art: the data-pools / pooledit
      blocks in the guided-controller tests). Full bats suite green.

## Blocked by

None - can start immediately.
