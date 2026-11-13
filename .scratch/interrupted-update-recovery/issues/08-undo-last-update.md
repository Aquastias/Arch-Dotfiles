# 08: Undo Last Update

Status: done

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** one "Undo Last Update" boot entry on all five loaders.
Choosing it rolls the Update Snapshot datasets back to the newest Update
Snapshot in the initramfs (after pool import and unlock, before the
Impermanence Rollback Hook), restores the matching Blank Snapshots on
Impermanence hosts, and boots the Primary Kernel's `-prev` pair. The entry
is absent while that pair is absent. Entries use stable names, so efistub
NVRAM entries are written once.

**Blocked by:** 01, 06, 07.

- [x] Bats: entry rendered for each of the five loaders; absent without a
      previous Primary Kernel pair
- [x] VM: complete an update, boot Undo, previous kernel and package
      versions are back, normal boot afterwards
- [x] VM on an Impermanence profile: `/etc` matches the rolled-back `/usr`
- [x] Retrofit adds the entry where the ESP holds a previous pair

## Comments

- Code + bats done: renderers for all five loaders, runtime reconcile
  (present only while the Primary Kernel's previous pair exists), the
  `undo-update` initramfs hook (behaviour-tested against a stub `zfs`), the
  post-Undo ESP re-sync unit, the rEFInd `dont_scan_files` line, the efistub
  firmware entry (`--create-only`), and the retrofit (template from the
  running cmdline, `undo-update` added to HOOKS, initramfs rebuilt on the
  live system).
- Every ZFS HOOKS list now carries `undo-update`, so its hook files are
  written before `mkinitcpio -P`.
- Open: both VM checks (need ticket 01). Also unverified until then: rolling
  back the mounted root inside the initramfs latehook.
- VM: Undo verified (scenario 4 in `.scratch/interrupted-kernel-upgrade/
  repro.md`) after two hook fixes. The Impermanence `/etc` check is blocked
  by a separate, pre-existing bug: the Pacman Resnapshot Hook never runs on
  Impermanence installs (its hook file is hidden under the `/etc/pacman.d`
  Persist Mount), so no Rollback Dataset ever gets an Update Snapshot.
- The Impermanence `/etc` blocker is fixed
  (`.scratch/impermanence-resnapshot-hook-hidden`); Rollback Datasets now
  carry `@update-*`. The `/etc` restore by Undo itself is not yet VM-run.
- Impermanence `/etc` check VM-run 2026-11-13: PASS (canary v1/v2 across
  `/etc` and `/usr`; Undo and the next normal boot both keep v1). See
  `.scratch/interrupted-kernel-upgrade/repro.md`.
