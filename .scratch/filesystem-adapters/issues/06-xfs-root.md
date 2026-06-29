# 06 — xfs root

Status: done
Type: AFK

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

Add xfs as an OS/root filesystem. It is the same shape as the ext4 root (single
partition, LUKS-optional, `root=UUID=…` / `root=/dev/mapper/cryptroot`, no native
topology, single-disk only) differing only in `mkfs.xfs`. Reuse the non-ZFS
partition/LUKS planner and the `ROOT_CMDLINE`/`HOOKS` machinery; the xfs Root
Layout Adapter should be a thin variant over the shared non-ZFS root path.

## Acceptance criteria

- [ ] A pure xfs install (plaintext) boots headless in a VM.
- [ ] An encrypted xfs root boots (live/HITL verify acceptable).
- [ ] The xfs adapter reuses the shared non-ZFS planner + emitters (no duplicated
      partition/LUKS logic).
- [ ] xfs is offered only as single-disk (no topology), enforced by the
      validation contract from issue 01.
- [ ] bats covers the xfs `ROOT_CMDLINE`/`HOOKS` emitter variants.

## Blocked by

- `04` (LUKS / shared non-ZFS root plumbing)
