# First-boot sentinel brick-precondition test

Status: done

## Parent

PRD: Boot-path resilience on a small FAT ESP
(`.scratch/boot-path-resilience-small-esp/PRD.md`). See ADR 0038.

## What to build

Prove the exact failure that bricked the reference machine cannot
silently return, using the VM Harness's existing first-boot sentinel
mechanism. A test profile's first-boot check plants the brick
precondition — a deliberately tight/filled ESP plus a planted Stray
Kernel — then runs the hardened ESP Kernel Sync and the warn hook, and
emits the success sentinel only if the guard fails loudly, the prior
image is preserved, and the stray is reported. No second reboot is
required.

## Acceptance criteria

- [x] A first-boot check constrains/fills the ESP and plants a Stray
      Kernel, then exercises the hardened hook.
- [x] The sentinel is emitted only when: the critical copy fails loudly
      on a full ESP, the prior image is preserved, and the Stray Kernel
      is reported by the warn hook.
- [x] The test fails (host sentinel timeout) if any guard does not fire.
- [x] Reuses the existing `firstboot-ok.service` sentinel + serial
      mechanism; no second reboot.

## Blocked by

- Issue 04 (ESP Kernel Sync PostTransaction hardening)
- Issue 06 (Stray Kernel warn hook)

## Comments

- 2026-09-27 audit: 54628ee (tests/vm/profiles/boot/resilience.jsonc + firstboot
  check).
