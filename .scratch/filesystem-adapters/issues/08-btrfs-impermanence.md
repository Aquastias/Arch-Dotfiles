# 08 — btrfs impermanence (per-path rollback, ADR 0044)

Status: ready-for-agent
Type: HITL

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

Bring impermanence to a btrfs root by mirroring the ZFS per-path rollback model
(ADR 0044), reusing the existing curated/persist/resnapshot machinery. Swap only
the three filesystem-specific primitives behind a filesystem switch: create the
rollback subvolumes, snapshot each to `@blank` (`btrfs subvolume snapshot -r`),
and the boot-time rollback (an initramfs `btrfs-rollback` hook that
`subvolume delete`s + recreates from `@blank` per path, failing closed to an
emergency shell on a missing `@blank`). Persist `.mount` units order `After=` the
btrfs root mount instead of `zfs-mount.service`. The curated lists, `persist_*`
bind-mount verbs, manifest, and the PostTransaction re-snapshot pacman hook are
reused verbatim.

HITL: the boot-time rollback needs a live reboot test (like the prior ZFS
impermanence work), not just a headless smoke.

## Acceptance criteria

- [ ] A btrfs root with impermanence enabled rolls the curated subtrees back to
      `@blank` on every boot; persisted paths and curated state survive.
- [ ] The `btrfs-rollback` initramfs hook fails closed to an emergency shell when
      a `@blank` snapshot is missing.
- [ ] Persist `.mount` units order after the btrfs root mount; machine-id / host
      keys / SOPS age key restore before early services (no dbus thrash).
- [ ] A package install survives a reboot (PostTransaction re-snapshot reused).
- [ ] The FS-agnostic impermanence layer (curated lists, persist verbs, manifest,
      resnapshot hook) is unchanged and shared with ZFS.
- [ ] bats covers the btrfs FS-layer (rollback-subvol creation, `@blank` snapshot
      calls, `btrfs-rollback` hook contents) with writes redirected under a temp
      ROOT, mirroring the existing ZFS impermanence tests.
- [ ] Live reboot test confirms rollback (HITL).

## Blocked by

- `07` (btrfs root boots)
