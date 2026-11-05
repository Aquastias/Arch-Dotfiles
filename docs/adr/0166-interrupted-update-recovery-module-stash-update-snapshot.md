# ADR 0166: Interrupted-update recovery: Module Stash + Update Snapshot

## Status
Accepted — not yet implemented. Amends [ADR 0038] and [ADR 0078].

## Context
A laptop restarted by itself during `pacman -Syu` while the post-install
hooks were running (2026-10-31). pacman had already removed the old
`linux-lts` modules and its preset, but `90-mkinitcpio-install` and the
[[ESP Kernel Sync]] never ran. The ESP still held the old kernel, which had
no modules on disk: `vfat` and `zfs` could not load, `/boot/efi` failed to
mount, and boot stopped in emergency mode. Recovery needed a live ISO, the
ZFS bootstrap, a chroot, and reinstalling `linux-lts` + `zfs-dkms` from the
cache.

Every install is exposed. All five Bootloader Adapters are ESP-mirroring
loaders (GRUB moved onto the ESP because it cannot read an encrypted rpool),
and the window between module removal and the ESP sync is how pacman works.
[ADR 0038] made the sync fail-closed, but it only covers a failed copy, not a
transaction that never reaches the copy.

## Decision
Goal: an [[Interrupted Kernel Transaction]] is recoverable without a USB
stick, on every ESP-mirroring loader and every Kernel Selection size.

1. **[[Module Stash]].** A PreTransaction hook, ordered before the dkms
   removal hooks, copies the modules (`zfs.ko` included) of every selected
   kernel whose version changes to a place outside every Rollback Dataset.
   Stray Kernels are skipped. The stash is dropped once the ESP Kernel Sync
   has succeeded.
2. **[[Stash Restore]].** An early-boot unit, ordered before module loading,
   restores the stash when `/usr/lib/modules/$(uname -r)` is missing. The
   kernel still on the ESP then boots normally. It announces the interruption
   on the console and as a desktop notification; it never runs pacman itself.
3. **[[Update Snapshot]]** (ZFS roots). A PreTransaction hook snapshots
   `rpool/ROOT/arch` and `rpool/var` as `@update-<UTC time>` before every
   transaction. Keep the last three. The snapshot taken before an unfinished
   transaction is exempt from pruning until a transaction completes. On
   Impermanence hosts the Rollback Datasets are *not* snapshotted: the
   boot-time `zfs rollback -r @blank` would destroy any newer snapshot.
   Their pre-update state is `@blank` itself, so the Pacman Resnapshot Hook
   renames the old `@blank` to the transaction's `@update-*` name instead of
   destroying it (a renamed snapshot keeps its creation time and survives
   the rollback). After an interrupted update `@blank` is still the
   pre-update state.
4. **Previous kernel pairs on the ESP.** Before every transaction (not only
   kernel ones), each staged kernel's current kernel + default initramfs is
   copied to stable `-prev` names when the `-prev` pair differs, so the
   previous pair always matches the state the Update Snapshot captures. A
   refresh only on kernel transactions would leave `-prev` a version behind
   the newest snapshot after any later non-kernel update. Stable names mean
   boot entries (and efistub NVRAM entries) are written once at install. If
   the ESP lacks room beside what the sync needs, the pair is skipped with a
   warning and the update proceeds.
5. **[[Undo Last Update]].** One boot entry: it rolls back to the newest
   Update Snapshot in the initramfs (an `undo-update` hook right after `zfs`,
   before `zfs-rollback`; on Impermanence hosts the kept Blank Snapshots
   become `@blank` again) and boots the Primary Kernel's matching pair. The
   entry is rendered once into a template and kept present only while that
   pair exists, so it never dead-ends; efistub instead gets one fixed
   firmware entry outside BootOrder. rEFInd is told not to scan the `-prev`
   kernels, which it would otherwise boot without the rollback. After an
   Undo boot a unit re-syncs the ESP from the rolled-back `/boot`, so the
   next normal boot matches. Older snapshots are reachable only from a live
   ISO.
6. **Battery preflight.** A PreTransaction hook aborts a kernel transaction
   on battery below 30% when not charging. No battery, no check.
7. **ESP budget** ([ADR 0078]) adds one previous pair (~100 MiB with the
   ZFS module) per selected kernel. Non-ZFS roots get items 1, 2, 4 and 6.
8. **Retrofit.** `tools/harden-boot.sh` installs all of the above on
   existing machines and learns all five bootloaders.

## Considered Options
- **Update Snapshot alone** — rejected: ZFS-only, and needs a menu choice
  plus a matching old kernel on the ESP; the stash makes the default entry
  just work for the common case.
- **Module Stash alone** — rejected: does not help an update that completes
  but leaves a broken system.
- **AUR `kernel-modules-hook`** — not adopted: it could not be confirmed
  against the Arch Wiki, and any restore done in a PostTransaction hook
  never runs when the transaction is interrupted.
- **Auto-finish the update at boot** — rejected: needs network and can fail
  unseen; a notification and one command are enough.
- **One Undo entry per kernel** — rejected: doubles the menu; after the
  rollback every kernel has its modules again.

## Consequences
- The default boot entry survives an Interrupted Kernel Transaction.
- Each kernel costs about 100 MiB more ESP; old small ESPs lose Undo, not
  updates.
- Every pacman transaction takes a ZFS snapshot; space is reclaimed as old
  snapshots are pruned.
- An on-demand VM test reproduces the interruption (snapshot the VM, cut off a
  kernel swap during its hooks, reset) and checks the Stash Restore boot and
  Undo Last Update.

<!-- ADR links: generated by readability.sh --fix-adr-links -->
[ADR 0038]: 0038-boot-path-resilience-small-esp.md
[ADR 0078]: 0078-per-kernel-entries-and-kernel-aware-esp-autosize.md
