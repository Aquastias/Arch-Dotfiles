# 04 — Cell generator + constraint model + mixed-fs + pinned seeds

Status: done
Type: AFK

## Parent

`.scratch/combination-matrix/PRD.md`

## What to build

The real generator. Sourcing the menu's own option functions
(`_ctl_topologies_for_fs`, `menu_rows`, picker/validation min-disk rules) and
the axis registry, produce two cell sets as JSON lines (cell-id + axis
assignment):

- **Tier-1 exhaustive storage cluster** — the full Cartesian of root filesystem
  × encryption × impermanence × topology × disk-mode × per-group data-pool
  filesystem/encryption, under the menu's exclusions. Includes **mixed-filesystem
  cells** (zfs root + btrfs/ext4/xfs data pool, ext4 root + zfs data pool) and
  **per-group encryption** crosses (root encrypted / pool plaintext and inverse).
- **Tier-2 pairwise set** — feed the install-affecting axes (storage cluster +
  kernel, bootloader, desktop, gpu, swap) through the pairwise reducer, then
  union the **pinned historical-bug seeds**: zfs-root+btrfs-pool,
  ext4-root+zfs-pool, btrfs-raid1-encrypted-multi, xfs-root,
  zfs-keyfile-on-root+encrypted-pool. GPU is a full axis {auto, amd, nvidia,
  intel}; pin `nvidia × kernel` as a mandatory pair.

Reachability comes only from the menu functions, so impossible cells are
structurally excluded. Independent scalars are swept once (each value appears in
≥1 cell) but not crossed against storage.

## Acceptance criteria

- [x] No emitted cell violates `_validation_topology_for_fs` or the min-disk
      rules (cross-checked in tests).
- [x] Every pinned seed tuple is present in the Tier-2 set; `nvidia × kernel`
      co-occurs in ≥1 cell.
- [x] Mixed-fs cells and per-group-encryption cells are present in Tier-1.
- [x] The Tier-1 set equals the exhaustive storage-cluster cross-product under
      the exclusions (asserted by construction/count).
- [x] Every independent scalar value (each kernel/bootloader/desktop/gpu, …)
      appears in at least one cell.
- [x] Output is deterministic for a fixed seed.

## Blocked by

- `.scratch/combination-matrix/issues/02-axis-registry-completeness.md`
- `.scratch/combination-matrix/issues/03-pairwise-reducer.md`

## Comments

**Done 2026-07-08 (TDD, LOCAL/UNPUSHED).** `lib/matrix/generator.sh` derives
axes from the menu's own functions (`_ctl_built_root_filesystems`,
`_ctl_topologies_for_fs`) — no drift.

- **Tier-1** `matrix_tier1_cells` — exhaustive cross-product: root fs × mode ×
  topology × enc × impermanence × a per-group data pool (fs/enc), under the menu
  exclusions. 360 cells; count asserted == the independently-recomputed product.
  Mixed-fs (zfs-root+btrfs-pool, ext4-root+zfs-pool, …) + per-group-enc (root
  enc/pool plain and inverse) present. AC1 cross-checked against the REAL
  `_validation_topology_for_fs` (distinct root-multi + data-pool topologies) +
  ext4/xfs single-disk. zfs single-disk pool topology = `none` (not `single`,
  which zfs rejects).
- **Tier-2** `matrix_tier2_cells [seed]` — pairwise cover (reducer, issue 03)
  over fs/topology/enc/imperm/kernel/bootloader/desktop/gpu/swap with
  menu-derived fs↔topology + ext4/xfs-imperm exclusions, ∪ 7 pinned seeds
  (zfs+btrfs-pool, ext4+zfs-pool, btrfs-raid1-enc-multi, xfs-root,
  zfs-keyfile-root+enc-pool, nvidia×{lts,zen}). 47 cells, deterministic
  (`unique_by(.id)`), every scalar value present, nvidia×kernel co-occurs.

**Graduation of slice-01 wiring:** `matrix.sh gen` now emits the committed
Tier-2 manifest (was the 1-cell tracer); `emit`/`run` resolve ids against
`matrix_all_cells` (tier1∪tier2); the assembler takes mode from the cell + makes
desktop optional (string→array). Tier-1 assembly bats now validates ALL FOUR
single-disk root filesystems via the real `validate_install_context`. Matrix
suite 29/29, shellcheck clean.

**Deferred to slice 05:** multi-disk + data-pool DISK ASSIGNMENT in the
assembler/synthesizer (emit/run bake single-disk today), and iterating the full
360-cell Tier-1 set through validate_install_context (needs the multi assembler).
