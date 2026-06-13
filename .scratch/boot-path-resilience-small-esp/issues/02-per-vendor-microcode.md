# Per-vendor microcode

Status: done

## Parent

PRD: Boot-path resilience on a small FAT ESP
(`.scratch/boot-path-resilience-small-esp/PRD.md`). See ADR 0038.

## What to build

Install and reference only the running machine's CPU microcode. Detect
the CPU vendor at install (the same approach GPU Resolution uses) and
add only the matching `*-ucode` to the Base Package List instead of
both unconditionally. Loader entries (systemd-boot) and the ESP Kernel
Sync derive their microcode `initrd` lines from the `*-ucode.img` files
that actually exist, so an entry can never reference a missing initrd. A
new "microcode resolution" deep module owns the pure vendor→package
mapping and the present-files→entry-lines logic. (GRUB already
enumerates only present microcode via grub-mkconfig.)

## Acceptance criteria

- [ ] CPU vendor detected at install; only the matching `*-ucode` is
      installed (Intel board → no `amd-ucode`, and vice-versa).
- [ ] systemd-boot loader entries list a microcode `initrd` only for a
      `*-ucode.img` that exists.
- [ ] Omitting the other vendor's microcode never produces a dangling
      `initrd` reference ("Error preparing initrd").
- [ ] VM / unknown CPU → no microcode referenced, install still succeeds.
- [ ] Bats cover vendor→package mapping and present-files→entry-`initrd`
      lines (including the missing-file case).

## Blocked by

None - can start immediately.
