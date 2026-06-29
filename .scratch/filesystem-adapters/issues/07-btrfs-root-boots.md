# 07 — btrfs root boots (no impermanence yet)

Status: done
Type: AFK

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

Add btrfs as an OS/root filesystem that installs and boots, deferring
impermanence to issue 08. Build the btrfs Root Layout Adapter: create the root
subvolume layout (`@`, `@home`, …), `mkfs.btrfs` with native topology
(single/raid0/raid1/raid10) when multiple disks are assigned, LUKS-optional, and
emit a `ROOT_CMDLINE` with `rootflags=subvol=…` plus the appropriate `HOOKS`.
Reuse the shared non-ZFS partition/LUKS planner.

## Acceptance criteria

- [ ] A btrfs root (plaintext) boots headless in a VM with the expected subvolume
      layout mounted.
- [ ] An encrypted btrfs root boots (live/HITL verify acceptable).
- [ ] Multi-disk btrfs groups create the native topology (raid1/raid10);
      single-disk uses `single`.
- [ ] `ROOT_CMDLINE` includes `rootflags=subvol=…`; `HOOKS` are correct (encrypt
      when encrypted; no zfs-rollback yet).
- [ ] bats covers the btrfs `ROOT_CMDLINE`/`HOOKS` emitter variants.

## Blocked by

- `04` (LUKS / shared non-ZFS root plumbing)
