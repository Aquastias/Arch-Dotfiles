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

- [x] A btrfs root with impermanence enabled rolls the curated subtrees back to
      `@blank` on every boot; persisted paths and curated state survive.
      *(FS-layer built; boot behaviour pending HITL reboot.)*
- [x] The `btrfs-rollback` initramfs hook fails closed to an emergency shell when
      a `@blank` snapshot is missing.
- [x] Persist `.mount` units order after the btrfs root mount; machine-id / host
      keys / SOPS age key restore before early services (no dbus thrash).
      *(After= owning per-path subvol mount; FILES still COPY-frozen in @blank.)*
- [x] A package install survives a reboot (PostTransaction re-snapshot reused
      hook file; btrfs resnapshot helper body) — *reboot survival pending HITL.*
- [x] The FS-agnostic impermanence layer (curated lists, persist verbs, manifest,
      resnapshot hook) is unchanged and shared with ZFS.
- [x] bats covers the btrfs FS-layer (rollback-subvol creation, `@blank` snapshot
      calls, `btrfs-rollback` hook contents) with writes redirected under a temp
      ROOT, mirroring the existing ZFS impermanence tests.
- [ ] Live reboot test confirms rollback (HITL).

## Progress (TDD, LOCAL/UNCOMMITTED)

Built via red→green slices; 1453 non-vm bats, 0 fail. Not yet committed.

- Slice 0: `FILESYSTEM` threaded through install-state (the FS-blind chroot
  modules' only discriminator).
- Rollback containers = subvolumes: `imp_btrfs_rollback_subvols` (from the same
  `ROLLBACK_DATASETS` source of truth) folds into the btrfs create/mount/fstab
  loops under impermanence (`@etc/@root/@opt/@srv/@usrlocal`). `/persist` is a
  plain dir on the never-rolled-back `@`.
- 3 FS-conditional primitives in `lib/chroot/impermanence.sh` (dispatch on
  `$FILESYSTEM`): `@blank` snapshot (`btrfs subvolume snapshot -r` over the
  subvolid=5 top-level), `btrfs-rollback` initramfs hook (`subvolume delete` +
  recreate from `@<name>@blank`, fail-closed on missing blank), PostTransaction
  resnapshot helper. zfs paths renamed `_zfs`, behaviour unchanged.
- Persist `.mount` After= → owning per-path subvol mount (`imp_mount_after_unit`:
  /etc/ssh→`etc.mount`, off-subvol→`-.mount`).
- HOOKS: `btrfs_hooks … impermanence` inserts `btrfs btrfs-rollback` before
  `filesystems` (no dup on multi); single+multi adapters pass the flag.
- Validation: `_validation_impermanence` skips the zfs `<pool>/<path>` rule for
  non-zfs (btrfs persist is a path, no pool).

Committed (local, UNPUSHED): `6f0b3fc` install-state FILESYSTEM, `629800b` btrfs
impermanence feature, `9698719` harness btrfs break-control.

Harness ready: `_seed_generator_rollback_firstboot_block` now takes a `filesystem`
arg (env `VM_ROLLBACK_FS=btrfs`) — btrfs seeds the sentinel via `subvol=@` mount
and the break-control deletes the `@etc@blank` subvol (subvolid=5 at /mnt), so the
automated two-boot `verify.rollback` test + its hook-fault negative control work on
btrfs. 1598 bats 0 fail.

Profiles ADDED (all resolve to configs passing `_validation_{filesystem,
group_filesystems,impermanence}`):
- `tests/vm/profiles/impermanence/btrfs.jsonc` — single, plaintext, verify.rollback.
- `tests/vm/profiles/impermanence/btrfs-raid1.jsonc` — 2-disk raid1, plaintext,
  verify.rollback. Harness `btrfs device scan`s before the live-ISO seed mount so
  the raid assembles.
- `tests/vm/profiles/impermanence/btrfs-encrypted.jsonc` — single, LUKS,
  INSTALL-ONLY (encrypted roots can't headless boot-verify — rollback HITL).
`vm.sh` auto-derives `VM_ROLLBACK_FS` from `install.filesystem` (no env override).

REMAINING (HITL — only open AC): run the live two-boot reboot test:
- baseline: `vm.sh -t tests/vm/profiles/impermanence/btrfs.jsonc --recreate`
  → boot2 emits `===FIRSTBOOT-OK===` (rollback reverted /root probe, /persist flag
  survived). Same for `btrfs-raid1.jsonc`.
- assertion control: same + `VM_ROLLBACK_PROBE_DIR=/persist` → probe survives →
  no marker → host RED (proves non-vacuous).
- hook-fault control: same + `VM_ROLLBACK_BREAK_BLANK=true` → boot1 deletes
  `@etc@blank` → boot2 hook fails closed (emergency shell) → RED.
- encrypted-single (`btrfs-encrypted.jsonc`): install-only → INSTALLER-EXIT-0,
  then boot by hand (`testtest`), manually do the two-boot probe/persist check.
Mirrors the ZFS 4-VM validation (`87b08f6`); enc-multi blocked (issue 07). Agent
env can't `git push` (~/.ssh denied) — USER pushes; VMs via `git daemon` +
`REPO_URL=git://192.168.122.1/.dotfiles`.

## Blocked by

- `07` (btrfs root boots)
