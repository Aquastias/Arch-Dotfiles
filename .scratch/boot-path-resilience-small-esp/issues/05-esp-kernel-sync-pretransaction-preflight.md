# ESP Kernel Sync PreTransaction preflight

Status: done

## Parent

PRD: Boot-path resilience on a small FAT ESP
(`.scratch/boot-path-resilience-small-esp/PRD.md`). See ADR 0038.

## What to build

Add a PreTransaction pacman hook that aborts a kernel upgrade before it
is applied when the ESP lacks room for the new images, so the system
never enters the bootable-but-degraded state where the package
transaction completed but the ESP still holds the old kernel's pair. It
reuses the planner's space proxy (a function of the current
Kernel-Selection images' sizes) to decide. On a 2G ESP it never fires;
it mainly protects retrofitted 512M machines.

## Acceptance criteria

- [ ] A kernel transaction with insufficient ESP free space is aborted at
      PreTransaction with a clear message to free space.
- [ ] On an ESP with ample room (e.g. 2G), the preflight never aborts a
      normal upgrade.
- [ ] The preflight and the PostTransaction guard share one space-proxy
      implementation (no duplicate logic).
- [ ] Bats cover the space-proxy / abort decision.

## Blocked by

- Issue 04 (ESP Kernel Sync PostTransaction hardening)
