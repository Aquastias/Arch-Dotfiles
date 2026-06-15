# Filesystem axis + Disks-owned encryption & impermanence

Status: ready-for-agent

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

Realize the **Filesystem Adapter** axis (ADR 0040) end-to-end, ZFS-only.
Add the top-level `filesystem` discriminator (default `zfs`; existing ZFS
layout fields stay flat at root). Add the additive
`options.encryption_method` (`native` | `luks`, default derived from
`filesystem`); the existing `options.encryption` bool still toggles
enablement. Generalize the layout dispatch to a **filesystem-keyed** seam
with ZFS as the only adapter (no behavioural change to the ZFS path). Add
`lib/config/validation.sh` contract checks: fields-set must match
`filesystem`; encryption method must match filesystem; Impermanence only
on ZFS/btrfs.

In the Guided Installer, the Disks section becomes **filesystem-first**
(btrfs/ext4/xfs shown as disabled/reserved entries). **Encryption** and
**Impermanence** move under Disks because the filesystem governs them.
Impermanence is offered only for ZFS/btrfs (hidden for ext4/xfs); when
enabled it applies the Curated Persist Defaults automatically and lets
the operator add Persist Extensions.

## Acceptance criteria

- [ ] Config carries `filesystem` (default `zfs`); existing ZFS profiles
      and VM seeds validate and install unchanged.
- [ ] `options.encryption_method` present (`native` | `luks`), default
      derived from `filesystem`; enablement still via the bool.
- [ ] Layout dispatch is filesystem-keyed; the ZFS path is unchanged in
      behaviour.
- [ ] Contract checks accept valid combinations and reject invalid ones
      (fields↔filesystem, method↔filesystem, impermanence↔filesystem)
      with the offending path.
- [ ] Disks menu is filesystem-first with btrfs/ext4/xfs disabled;
      Encryption + Impermanence sit under Disks; Impermanence hidden for
      ext4/xfs.
- [ ] Enabling Impermanence applies Curated Persist Defaults and supports
      adding Persist Extensions.
- [ ] bats: contract checks + emit.

## Blocked by

- `01-guided-install-tracer-bullet`
