# zswap controls in swapedit + summary suffix

Status: ready-for-agent

## Parent

`.scratch/swap-zswap-unified/PRD.md`

## What to build

Expose the zswap settings in the `swapedit` sub-screen so the operator can edit
what issue 02 made active by default, and extend the swap row summary to reflect
zswap state.

New swapedit rows, with conditional visibility (hidden when moot — consistent with
how the impermanence row is hidden for ext4/xfs; never shown disabled):

- `zswap` — Enter toggles `options.zswap.enabled` on/off; shown only when swap is
  on.
- `compressor` — Enter cycles `zstd → lz4 → lzo → zstd`; shown only when zswap is
  on.
- `max pool %` — Enter cycles `5 → 10 → 20 → 40 → 60 → 5`; shown only when zswap
  is on.

The swap row's one-line summary gains a zswap suffix: append `· zswap
<compressor>` when zswap is on, or `· no zswap` when zswap is off. Examples:
`auto · zswap zstd` (default), `8G · no zswap`, `off`.

All edits flow through the existing Config State write + autocommit path
(undo/redo/reset already cover them).

## Acceptance criteria

- [ ] The `zswap` row appears only when swap is on and toggles
      `options.zswap.enabled`.
- [ ] The `compressor` row appears only when zswap is on and cycles
      `zstd → lz4 → lzo`.
- [ ] The `max pool %` row appears only when zswap is on and cycles
      `5 / 10 / 20 / 40 / 60`.
- [ ] When swap is off, none of the zswap rows are shown.
- [ ] The swap row summary renders `off`; `<size> · zswap <compressor>` when
      zswap on; `<size> · no zswap` when zswap off.
- [ ] Controller bats cover the toggles, cycles, conditional visibility, and the
      summary label (prior art: data-pools / pooledit controller tests). Full
      bats suite green.

## Blocked by

- `.scratch/swap-zswap-unified/issues/01-unified-swap-row-swapedit.md`
- `.scratch/swap-zswap-unified/issues/02-zswap-activation-boot-layer.md`
