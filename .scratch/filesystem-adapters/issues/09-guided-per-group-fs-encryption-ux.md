# 09 — Guided Installer per-group filesystem/encryption UX + gating

Status: ready-for-human
Type: HITL

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

Surface the filesystem axis in the Guided Installer. Add a root-filesystem picker
that lists **only filesystems whose adapter is built** (ZFS now; ext4/xfs/btrfs
as their slices land), make topology lists filesystem-conditional (zfs →
mirror/raidz; btrfs → single/raid0/1/10; ext4/xfs → single only), and add a
per-group filesystem + encryption choice in the data-pool editor. Hide/disable the
impermanence toggle unless the root filesystem is snapshotting (zfs/btrfs).

HITL: fzf live render + interactive flow review, consistent with the prior Guided
Installer work. Can land incrementally and grow as adapters appear.

## Acceptance criteria

- [x] The root-filesystem picker offers only built adapters; picking one updates
      the available topology, encryption method, and impermanence availability.
- [x] The data-pool editor offers a per-group filesystem and an encryption toggle;
      ext4/xfs groups are pinned to single-disk.
- [x] The impermanence toggle is hidden/disabled for ext4/xfs roots.
- [x] Choices author a valid Config State that assembles into an Effective Config
      passing the issue-01 validation contract.
- [ ] HITL live-test of the fzf flow confirms the per-group screens render and
      re-enter correctly. *(only open AC — needs a tty)*

## Progress (TDD, 2026-07-03 — LOCAL/UNPUSHED)

All four adapters (zfs/btrfs/ext4/xfs) are built (issues 05–08), so the picker
now offers all four. Both front-ends updated (interactive persistent-fzf
controller AND the headless `--guided` replay). 5 red→green slices, full suite
1615 bats 0 fail, shellcheck clean:

- **`5a954ef` Slice 1 — root-fs picker offers built adapters.** Dropped the
  `(reserved)` placeholders: `_ctl_enum_options filesystem` +
  `_ctl_apply_enum` (controller) now list/commit any BUILT fs via
  `_ctl_built_root_filesystems`; the replay path's `_GUIDED_FS_ACTIVE` gets all
  four. Both kept in lockstep with `lib/layout/dispatch.sh` (source of truth).
- **`2a902ff` Slice 2 — impermanence gating.** Already implemented in
  `menu.sh` (row hidden for ext4/xfs; Slice 1 made it reachable); filled the
  xfs + zfs coverage gap.
- **`a104ae5` Slice 3 — fs-conditional topology.** `_ctl_topologies_for_fs`
  (matches `_validation_topology_for_fs`): zfs mirror/raidz1/raidz2/stripe;
  btrfs single/raid0/raid1/raid10; ext4/xfs single. The pool editor's topology
  cycle follows the group's own filesystem (pool value → root → zfs).
- **`41edbce` Slice 4 — per-group fs + encryption in the pool editor.** New
  `filesystem:`/`encryption:` rows in `pooledit`; `_ctl_pool_normalise_fs` pins
  ext4/xfs to single-disk (topology single, disk_count 1) and resets a stale
  topology on an fs change; the disks cycle is a no-op for ext4/xfs.
- **`fc5dc9c` Slice 5 (AC4) — assembly validates.** Integration test: authoring
  via the editor yields a Config State passing `_validation_group_filesystems` +
  `_validation_filesystem`; the pin is proven load-bearing (an ext4 group with
  disk_count 2 is rejected).

REMAINING (AC5, HITL — needs a tty/fzf): live-drive the flow to eyeball the
render + re-entry. Interactive: `tools/guided-preview.sh` (or `install.sh
--guided`), then: pick each root fs; confirm the impermanence row appears only
for zfs/btrfs; open Disks → layout → data-pools → a pool and cycle
`filesystem:`/`topology:`/`encryption:`, confirming ext4/xfs pin disks to 1.
Commits LOCAL/UNPUSHED — USER pushes.

## Blocked by

- `01` (schema/validation); grows as adapters `03`–`08` land
