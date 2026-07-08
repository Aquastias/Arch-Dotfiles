# 04 — Cell generator + constraint model + mixed-fs + pinned seeds

Status: ready-for-agent
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

- [ ] No emitted cell violates `_validation_topology_for_fs` or the min-disk
      rules (cross-checked in tests).
- [ ] Every pinned seed tuple is present in the Tier-2 set; `nvidia × kernel`
      co-occurs in ≥1 cell.
- [ ] Mixed-fs cells and per-group-encryption cells are present in Tier-1.
- [ ] The Tier-1 set equals the exhaustive storage-cluster cross-product under
      the exclusions (asserted by construction/count).
- [ ] Every independent scalar value (each kernel/bootloader/desktop/gpu, …)
      appears in at least one cell.
- [ ] Output is deterministic for a fixed seed.

## Blocked by

- `.scratch/combination-matrix/issues/02-axis-registry-completeness.md`
- `.scratch/combination-matrix/issues/03-pairwise-reducer.md`
