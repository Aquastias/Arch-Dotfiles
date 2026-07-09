# 03 — Bind-all: OS pool, storage groups, single-disk root

Status: done
Type: AFK

## Parent

`.scratch/guided-disk-binding-custom-layouts/PRD.md`

## What to build

Extend In-Menu Disk Binding from data pools to **every** group, so on-target a
fully specified layout needs no post-menu disk pick and no disk is double-claimed
across the OS root and data pools.

- **OS pool** — editable in the pool editor with topology + disks rows; its disks
  bind from the same global Free Set. (Root filesystem and root encryption stay
  at their existing top-level rows — not duplicated here.)
- **Storage groups** — appear in the editor as **binding-only**: their disks bind
  from the Free Set, but topology/mount/name/existence stay preset-fixed and
  display-only.
- **Single-disk root** — on-target, the Disks screen grows a `root disk:` row
  that single-selects one disk from the Free Set; `mode:single` off-target and
  replay keep the existing post-menu single-disk path.

All groups share the one global Free Set from slice 02, so a disk bound anywhere
disappears everywhere.

## Acceptance criteria

- [x] The OS pool is reachable in the editor and exposes topology + disks rows;
      binding its disks writes `os_pool.devices[]` with derived count (pure +
      fzf-entry seams).
- [x] A preset storage group shows a disks row that binds from the Free Set;
      topology/mount/name are display-only (no cycle emitted).
- [x] On-target single mode shows a `root disk:` row that single-selects one disk;
      off-target/replay single mode is unchanged.
- [x] Binding a disk to the OS pool removes it from the Free Set offered to data
      pools and storage groups, and vice versa (pure seam).
- [x] Full existing bats suite stays green.

## Blocked by

- 02 — Bind real disks to a data pool (device-mode tracer).
