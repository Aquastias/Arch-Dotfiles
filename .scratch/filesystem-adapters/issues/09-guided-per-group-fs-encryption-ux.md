# 09 — Guided Installer per-group filesystem/encryption UX + gating

Status: ready-for-agent
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

- [ ] The root-filesystem picker offers only built adapters; picking one updates
      the available topology, encryption method, and impermanence availability.
- [ ] The data-pool editor offers a per-group filesystem and an encryption toggle;
      ext4/xfs groups are pinned to single-disk.
- [ ] The impermanence toggle is hidden/disabled for ext4/xfs roots.
- [ ] Choices author a valid Config State that assembles into an Effective Config
      passing the issue-01 validation contract.
- [ ] HITL live-test of the fzf flow confirms the per-group screens render and
      re-enter correctly.

## Blocked by

- `01` (schema/validation); grows as adapters `03`–`08` land
