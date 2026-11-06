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

(filled in per run)
