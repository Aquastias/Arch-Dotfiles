# PRD: Interrupted-update recovery

Status: ready-for-agent

References: ADR 0166 (this feature), ADR 0038 (fail-closed ESP Kernel Sync,
preflight), ADR 0078 (per-kernel entries, ESP budget), ADR 0077 (five
ESP-mirroring Bootloader Adapters). Glossary: Interrupted Kernel
Transaction, Module Stash, Stash Restore, Update Snapshot, Undo Last
Update, ESP Kernel Sync, ESP-mirroring loader, Kernel Selection, Primary
Kernel, Stray Kernel, Rollback Datasets, Blank Snapshot, Pacman Resnapshot
Hook.

## Problem Statement

A laptop installed by an older installer restarted by itself during
`pacman -Syu`, while the post-install hooks were running. pacman had already
removed the old `linux-lts` modules and its mkinitcpio preset, but the
initramfs build and the ESP Kernel Sync never ran. On the next boot the
loader started the old kernel still on the ESP. That kernel had no modules on
disk, so `vfat` and `zfs` could not load, `/boot/efi` failed to mount, and
the machine stopped in emergency mode. The root password did not get past
the emergency prompt either.

Getting it back took an Arch ISO, the repo's ZFS bootstrap, a forced pool
import, a chroot, removing pacman's lock, and reinstalling `linux-lts` and
`zfs-dkms` from the package cache. That was about an hour of guided work for
someone who knows the system.

Every install made by the current installer is exposed the same way. All
five bootloaders boot a kernel mirrored onto the ESP, and every kernel
upgrade has a window between module removal and the ESP sync. Neither
ADR 0038's fail-closed sync nor the ESP space preflight helps when the
transaction never reaches the sync.

## Solution

An Interrupted Kernel Transaction no longer needs a USB stick:

- Before a kernel transaction, the old modules of every selected kernel
  whose version changes are kept aside (the **Module Stash**). If the
  machine dies mid-update, the next boot restores them early (the **Stash
  Restore**). The default boot entry then just boots, and the user is told to
  run `sudo pacman -Syu` to finish.
- On ZFS roots, every pacman transaction is preceded by an **Update
  Snapshot**. One boot-menu entry, **Undo Last Update**, returns the system
  to the newest one and boots the matching previous kernel, which the ESP
  Kernel Sync now keeps. This also covers an update that finished but left
  the system broken.
- A kernel transaction is refused on low battery when not charging.
- Existing machines get all of this through the boot-hardening retrofit
  tool, for every bootloader.

## User Stories

1. As an operator, I want my laptop to boot normally after it lost power
   during a kernel upgrade, so that I never need a live ISO for this.
2. As an operator, I want the kernel still on the ESP to find its modules
   after an interrupted upgrade, so that `vfat`, `zfs` and drivers load.
3. As an operator, I want a clear console message at boot saying the last
   update was interrupted, so that I know what happened.
4. As a desktop user, I want a notification after login saying the last
   update was interrupted, so that I see it even with a quiet boot.
5. As an operator, I want the message to tell me the one command that
   finishes the update, so that I don't have to diagnose anything.
6. As an operator, I want the system never to run pacman on its own after an
   interruption, so that nothing changes behind my back or fails unseen
   without network.
7. As an operator with several kernels selected, I want every selected
   kernel whose version changed to be protected, so that any boot entry I
   pick still works.
8. As an operator, I want Stray Kernels ignored by the stash, so that
   kernels that never reach the ESP don't cost space or time.
9. As an operator, I want the stash to also hold the old kernel's ZFS
   module, so that the old kernel can still mount ZFS datasets after boot.
10. As an operator, I want the stash taken before dkms removes the old ZFS
    module, so that the stash is complete.
11. As an operator, I want the stash dropped automatically once the new
    kernel is safely on the ESP, so that it never piles up.
12. As an operator on an Impermanence host, I want the stash kept outside
    every Rollback Dataset, so that the boot-time rollback doesn't wipe it.
13. As an operator, I want the Stash Restore to do nothing on a normal boot,
    so that it never touches a healthy system.
14. As an operator, I want the Stash Restore to run before anything loads a
    module, so that the restored modules are used on that same boot.
15. As an operator on a ZFS root, I want a snapshot before every pacman
    transaction, so that any update, not only kernel ones, can be undone.
16. As an operator, I want the snapshot to cover the root, `/var`, and on
    Impermanence hosts the Rollback Datasets, so that `/usr`, the package
    database and `/etc` roll back together.
17. As an operator, I want `/home`, `/tmp`, `/var/cache` and `/var/log` left
    out of the snapshot, so that undoing an update never loses my files or
    the logs that explain the failure.
18. As an operator, I want only the last three Update Snapshots kept, so that
    snapshots don't eat the pool.
19. As an operator, I want the snapshot taken before an unfinished update
    protected from cleanup until an update completes, so that retrying a
    broken update can't push out the last good state.
20. As an operator, I want an "Undo Last Update" boot entry, so that I can
    recover from a bad update from the boot menu.
21. As an operator, I want Undo Last Update to boot the Primary Kernel's
    previous version, so that the kernel matches the rolled-back modules.
22. As an operator on an Impermanence host, I want Undo Last Update to also
    restore the matching Blank Snapshots, so that `/etc` agrees with `/usr`.
23. As an operator, I want a single Undo entry, not one per kernel, so that
    the boot menu stays short.
24. As an operator, I want the Undo entry hidden when there is no previous
    Primary Kernel to boot, so that I'm never offered an entry that fails.
25. As an operator, I want older Update Snapshots still on the pool, so that
    I can reach them from a live ISO if needed.
26. As an operator, I want the ESP to keep one previous kernel + initramfs
    for each selected kernel that changed, so that Undo has a kernel that
    matches the snapshot.
27. As an operator, I want unchanged kernels to keep using their current
    files, so that no ESP space is spent on duplicates.
28. As an operator using efistub, I want the previous-kernel files under
    stable names, so that firmware boot entries are written once and never
    rewritten on updates.
29. As an operator with a small ESP, I want a previous pair skipped with a
    warning when it doesn't fit, so that updates never fail because of Undo.
30. As an operator installing fresh, I want the ESP sized for one previous
    pair per selected kernel, so that Undo works out of the box.
31. As a laptop user, I want a kernel transaction refused on battery below
    30% when not charging, so that a dying battery can't cause the
    interruption.
32. As a desktop user with no battery, I want no battery check at all, so
    that nothing blocks my updates.
33. As a laptop user, I want non-kernel updates never blocked by the battery
    check, so that small updates still go through.
34. As an operator on a btrfs or ext4 root, I want the Module Stash, Stash
    Restore, previous kernels and battery check too, so that the main
    failure is covered without ZFS.
35. As an operator with an existing install, I want the retrofit tool to add
    all of this, so that I don't need to reinstall.
36. As an operator with limine, refind or efistub, I want the retrofit tool
    to recognise my loader, so that it doesn't refuse or do half the job.
37. As an operator, I want the retrofit tool to stay idempotent with a
    dry-run preview, so that I can run it safely more than once.
38. As a maintainer, I want an on-demand VM test that interrupts a kernel
    swap and checks the next boot, so that a regression is caught before it
    reaches a laptop.
39. As a maintainer, I want that VM test to also check Undo Last Update, so
    that the rollback path is proven, not assumed.
40. As a maintainer, I want the decision logic testable without a real
    machine, so that bats covers every branch quickly.
41. As a maintainer, I want the glossary and ADR 0166 to describe the
    feature, so that future changes respect it.

## Implementation Decisions

- **One new boot-recovery module** in the shared boot library, single
  source for installer and retrofit (the ADR 0023 pattern), lib-only
  sourceable. It owns:
  - the stash plan: given the kernels in a transaction, the Kernel
    Selection and the installed modules, which kernels to stash; Stray
    Kernels excluded;
  - the stash and its drop after a successful ESP Kernel Sync;
  - the Stash Restore decision and action: restore only when the running
    kernel's modules directory is missing and a stash for it exists, then
    rebuild module dependencies;
  - the battery decision: refuse only for a kernel transaction, with a
    battery present, below 30%, and not charging.
- **Module Stash hook**: a PreTransaction pacman hook on kernel image paths,
  ordered before the dkms removal hooks. The stash lives on the persistent
  OS dataset, outside every Rollback Dataset.
- **Stash Restore unit**: an early systemd unit, shipped in the vendor unit
  directory (not `/etc`, which Impermanence rolls back), ordered before
  module loading. After a restore it marks the boot so a console message and
  a post-login desktop notification are shown. It never runs pacman.
- **Battery preflight**: a PreTransaction hook with AbortOnFail on kernel
  image paths.
- **Update Snapshot hook** (ZFS roots only): a PreTransaction hook on every
  transaction. A pure planner turns the dataset list and Impermanence state
  into datasets to snapshot (root, `/var`, Rollback Datasets on Impermanence
  hosts) and snapshots to prune (keep three). The snapshot before an
  unfinished transaction is exempt from pruning until a transaction
  completes. Excludes `/home`, `/tmp`, `/var/cache`, `/var/log` and data
  pools.
- **ESP Kernel Sync extension** (amends ADR 0038): for each selected kernel
  whose version changes, keep the replaced kernel + default initramfs under
  stable `-prev` names. No previous fallback image. If the space preflight
  finds no room, the pair is skipped with a warning and the transaction
  proceeds. Existing temp-then-rename and verification apply to the
  previous pair too.
- **Undo Last Update entry**: generated by the loader-entry module for all
  five loaders, one entry, booting the Primary Kernel's `-prev` pair with a
  rollback kernel parameter. Absent when that pair is absent.
- **Initramfs rollback hook**: on the rollback parameter, after the pool
  import and unlock, roll back the Update Snapshot datasets to the newest
  Update Snapshot; on Impermanence hosts also restore the matching Blank
  Snapshots. It runs before the Impermanence Rollback Hook and must not
  conflict with it.
- **ESP budget extension** (amends ADR 0078): about 100 MiB per selected
  kernel for one previous pair (kernel + default initramfs + ZFS module
  surcharge).
- **Retrofit**: the boot-hardening tool installs every artifact above,
  detects all five loaders, stays idempotent with a dry-run preview, and
  writes the Undo entry only where the loader supports it on that ESP.
- Applies to every ESP-mirroring loader (all five, including GRUB).

## Testing Decisions

- Good tests check external behaviour only: files present or absent in a
  fake root or ESP, decisions printed, entries rendered. Never which
  internal helper ran.
- **New boot-recovery module, bats against temp directories** (fake modules
  tree, fake ESP, fake power-supply class directory):
  - stash plan: changed selected kernels stashed, unchanged and Stray
    Kernels not;
  - Stash Restore: restores only when modules are missing and a stash
    exists; no-op otherwise; no-op without a stash;
  - stash drop after a successful sync;
  - battery: refuse / allow across battery absent, charging, discharging
    above and below 30%, non-kernel transaction.
- **Update Snapshot planner, bats with fake `zfs list` output**: dataset
  selection with and without Impermanence, keep-three pruning, protection
  of the snapshot before an unfinished transaction.
- **Extend existing bats files**:
  - ESP Kernel Sync: `-prev` pairs only for changed kernels, stable names,
    skip with warning when short;
  - ESP budget: previous-pair allowance per kernel;
  - loader entries: Undo entry for each of the five loaders, absent without
    a previous Primary Kernel pair;
  - harden-boot: retrofit plan for all five loaders, idempotence.
- **On-demand VM test**: snapshot the VM, swap linux-lts version, cut the
  transaction off during its hooks, hard reset, assert a normal boot via the
  Stash Restore and the notice; then a completed update, Undo Last Update,
  assert the previous kernel and rolled-back package versions. Heavy, not in
  every matrix run; follow the repo's VM memory rules. The recipe starts
  from `.scratch/interrupted-kernel-upgrade/repro.md` once written.
- Prior art: the ESP Kernel Sync, Stray Kernel, ESP budget, loader entries
  and harden-boot bats suites (lib-only sourcing, temp ESP/boot dirs); the
  ZFS import tests that write units into a temp root.

## Out of Scope

- The emergency-shell root password not being accepted. Separate issue.
- Undo for btrfs or ext4 roots.
- Undoing anything older than the newest Update Snapshot from the boot menu.
- Automatically finishing an interrupted update.
- Preventing thermal shutdowns.
- Snapshots of data pools, `/home`, `/var/log`, `/var/cache`.
- A previous fallback initramfs on the ESP.

## Further Notes

- Field incident 2026-10-31: the pacman log ended right after the cronie
  hook; `db.lck` was left behind; the running kernel was 6.18.40 while only
  6.18.60 modules were on disk; `/etc/mkinitcpio.d` had no preset.
- Reinstalling `linux-lts` and `zfs-dkms` from the cache in a chroot reran
  every hook and fixed it; that is the manual fallback until this ships.
- The Arch Wiki could not be fetched for `kernel-modules-hook` (bot
  protection); ADR 0166 records why it was not adopted.
- Roll out to the laptop and the desktop through the retrofit tool once
  done.
