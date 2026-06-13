# Extract ESP Kernel Sync + drive from Kernel Selection

Status: done

## Parent

PRD: Boot-path resilience on a small FAT ESP
(`.scratch/boot-path-resilience-small-esp/PRD.md`). See ADR 0038, ADR
0023.

## What to build

Relocate the ESP Kernel Sync hook out of the systemd-boot Bootloader
Adapter heredoc into the shared boot-resilience artifact directory (ADR
0023's single-source pattern, with a lib-only-source guard so its logic
is testable), and change what it copies: only the kernels in the host's
Kernel Selection, never a `linux*` glob. A Stray Kernel therefore never
reaches the ESP. Also correct the hook ordering so the ESP Kernel Sync
runs before the ESP Mirror Hook — the current `95`/`96` numbering runs
the mirror first, so secondary ESPs would receive stale images.

## Acceptance criteria

- [ ] The ESP Kernel Sync script lives in the shared artifact location,
      sourced by the systemd-boot adapter; no behavior change beyond the
      items below.
- [ ] The hook copies only Kernel-Selection kernels' images; an
      installed Stray Kernel's `vmlinuz`/`initramfs` are never copied to
      the ESP.
- [ ] On a multi-disk OS layout, the ESP Kernel Sync runs before the ESP
      Mirror Hook (verified by hook ordering).
- [ ] A fresh systemd-boot install still boots (no regression).
- [ ] The shared artifact is lib-only-sourceable for tests.

## Blocked by

None - can start immediately.
