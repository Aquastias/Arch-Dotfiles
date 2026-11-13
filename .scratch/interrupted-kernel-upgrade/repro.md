# Interrupted Kernel Transaction: VM recipe

Ticket: `.scratch/interrupted-update-recovery/issues/01-vm-reproduction.md`.
ADR 0166. Field incident: a laptop reset itself during `pacman -Syu`'s
post-install hooks, before the initramfs build and the ESP Kernel Sync.

## Host rules

- One VM at a time. Before starting: `free -h` must show the VM's RAM
  (4 GiB) + 8 GiB available. Nothing heavy beside it. `vm-agent.sh stop`
  when done.
- Run every VM command with the sandbox disabled.

## The lab VM

```
.installer/vm/vm.sh --profile boot/interrupted-update --recreate --local
```

ZFS root, systemd-boot, Impermanence, headless, 4 GiB (profile
`vm/profiles/boot/interrupted-update.jsonc`). Drive it with
`.installer/vm/vm-agent.sh --vm arch-interrupted-update ssh '<cmd>'`.

## The interruption

A kernel version swap (`pacman -U` of another linux-lts + headers from the
Arch Linux Archive), cut off by a temporary PostTransaction hook that sleeps,
then a hard power-off (`virsh destroy`) while it sleeps:

- `59-hold.hook`: before `60-depmod` (the old modules dir survives holding
  depmod's unowned `modules.*`).
- `80-hold.hook`: after depmod and dkms, before `90-mkinitcpio-install` and
  `94-esp-kernel-sync` (the field case: old modules dir gone).

```
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = TEST: hold the transaction here
When = PostTransaction
Exec = /usr/bin/sleep 3600
```

Wait for `TEST: hold` in the pacman output, then `virsh destroy`, then
`virsh start`.

## Scenarios

1. **Baseline, no fix** (proves the test catches the bug): move
   `/etc/pacman.d/hooks/05-module-stash.hook` aside, swap with `80-hold`.
   Expect: emergency mode; running kernel has no `kernel/` tree on disk.
2. **Stash Restore, field case** (`80-hold`, stash hook in place). Expect:
   normal boot to `multi-user.target`; `boot-recovery-restore.service` ran;
   the console shows the notice naming `sudo pacman -S linux-lts`; running
   that finishes the update (ESP gets the new kernel, `.stash` gone); reboot
   boots the new kernel.
3. **Stash Restore, before depmod** (`59-hold`). Same expectations.
4. **Undo Last Update**: a completed swap that also installs a canary package
   with an `/etc` file. Then `bootctl set-oneshot arch-undo.conf` + reboot.
   Expect: old kernel running; `pacman -Q` shows the pre-update versions;
   the canary package and its `/etc` file are gone (Blank Snapshot
   restored); `undo-last-update-resync.service` re-synced the ESP; the next
   normal boot runs the old kernel cleanly.

## Results

Run 2026-11-06, lab VM from local HEAD, linux-lts 6.18.60 <-> 6.18.59 from
the cache and the Arch Linux Archive, `zfs-dkms` (the field config; the
install's prebuilt `zfs-linux-lts` is pinned to one kernel). Root SSH: the
inline profile creates no user, so the harness key was added for root via
the serial console.

| # | Scenario | Result |
|---|----------|--------|
| 1 | Baseline, stash hook removed, `80-hold` | EMERGENCY: `Failed to mount /boot/efi` — the field failure reproduced |
| 2 | Stash Restore, `80-hold` | PASS: normal boot, restore + notice; finish completed, new kernel boots |
| 3 | Stash Restore, `59-hold` (dir survives with depmod files) | PASS: filled in place, no nesting, `zfs`/`vfat` load |
| 4 | Undo Last Update | PASS after two hook fixes: old kernel, old package db, canary gone, ESP re-synced, next normal boot clean |

Findings fixed from these runs:
- Undo hook looked for the root at `/new_root`; this initramfs mounts it at
  `/sysroot`. Now taken from `root=ZFS=` on the cmdline.
- The initramfs busybox has no `tr`; the hook parses with builtins and its
  bats harness runs with PATH limited to the verified tools.
- The interrupted transaction leaves `db.lck`; the `/var` Update Snapshot
  (taken mid-transaction) restores it on Undo. A boot unit now clears it.
- `pacman -S <kernel>` is the wrong finish (repo may be newer than the
  headers; reinstalling a restored version conflicts). New command:
  `boot-recovery.sh finish` (installed versions from the cache).

Found, not part of this feature:
- Impermanence: `/etc/pacman.d` is a Persist Mount copied to `/persist`
  before `zz-impermanence-resnapshot.hook` is written, so the Pacman
  Resnapshot Hook never runs; `@blank` is never refreshed after updates.
- The ESP Kernel Sync triggers only on kernel images: an initramfs rebuilt
  by a zfs-dkms or mkinitcpio update never reaches the ESP.

Rerun on a VM rebuilt from HEAD (stale-lock unit + `finish`): field case
(`80-hold`) → normal boot; `boot-recovery-unlock` removed the stale
`db.lck`; the notice names `boot-recovery.sh finish`. With the exact versions
neither cached nor in the repo, `finish` refuses and changes nothing; with
them cached it reinstalls them, the ESP Kernel Sync drops the stash and the
leftover tree, and the next boot runs the new kernel. PASS.

Run 2026-11-06 (VM rebuilt from HEAD) for the two older bugs:
- Resnapshot hook live in `/etc/pacman.d/hooks`; after the `zfs-dkms`
  switch `@blank` was re-taken and `ROOT/etc`, `ROOT/opt` carry
  `@update-*`. PASS.
- `zfs-dkms` switch (no kernel change): ESP initramfs matches `/boot`. PASS.
- Stash guard: after an interrupted kernel update, an unrelated
  `pacman -U tree` left the stash and the restored tree; `finish` then
  completed and the new kernel booted. PASS.

Run 2026-11-13 (VM rebuilt from HEAD, `zfs-dkms`), the Impermanence `/etc`
check for Undo (ticket 08): canary package `undo-canary` (`backup=` file
`/etc/undo-canary.conf` on the `ROOT/etc` Rollback Dataset, plus
`/usr/share/undo-canary/version`) at v1; one transaction updating
linux-lts 6.18.63-2 → 63-3 (Arch Linux Archive) and the canary to v2. Undo
(`bootctl set-oneshot arch-undo.conf`): kernel 63-2, `pacman -Q` canary 1,
`/etc` says `version=1` and `/usr` says `1`; system `running`, ESP re-sync
ran, no `db.lck`. The next normal boot (Impermanence Rollback to `@blank`)
keeps `/etc` at v1 and runs 63-2, no failed units. PASS.
Note: the inline profile has no harness key in the installed guest; it was
added for root by serving a key script and typing `curl …|bash` on the
console (the console typer maps only `a-z0-9 ./-:|`).
