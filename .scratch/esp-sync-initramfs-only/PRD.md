# ESP Kernel Sync misses initramfs-only rebuilds

Status: done

## Problem

`94-esp-kernel-sync.hook` triggers only on `usr/lib/modules/*/vmlinuz`. An
update that rebuilds the initramfs without a kernel change — `zfs-dkms`, a
module package, mkinitcpio itself, firmware — updates `/boot` but never the
ESP, which keeps booting the old initramfs. A ZFS version bump then boots an
initramfs whose `zfs.ko` is older than the userland.

Seen in the interrupted-update VM runs (2026-11-06): after switching to
`zfs-dkms`, `/boot/initramfs-linux-lts.img` differed from the ESP copy.

## Fix (to design)

- Trigger the sync on every path `90-mkinitcpio-install` triggers on, so
  every initramfs rebuild reaches the ESP; keep the PreTransaction preflight
  aligned (ADR 0038).
- Tests: the sync hook's targets cover mkinitcpio's install-hook targets.

## Comments

- Fixed: the sync hook triggers on every transaction (drift-proof vs.
  copying mkinitcpio's target list) and skips identical files; the stash is
  dropped only when every ESP kernel matches `/boot`. ADR 0166 item 10.
