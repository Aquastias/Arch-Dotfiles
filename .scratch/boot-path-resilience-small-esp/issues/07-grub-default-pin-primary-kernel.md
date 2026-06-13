# GRUB default-pin to Primary Kernel

Status: ready-for-agent

## Parent

PRD: Boot-path resilience on a small FAT ESP
(`.scratch/boot-path-resilience-small-esp/PRD.md`). See ADR 0038.

## What to build

Ensure GRUB always boots the Primary Kernel by default, even when a
Stray Kernel sorts higher by version and would otherwise become the top
menu entry. The GRUB common installer pins `GRUB_DEFAULT` to the Primary
Kernel's entry rather than index 0. The stray remains a selectable menu
entry. Per-vendor microcode in GRUB is already handled by grub-mkconfig
enumerating present files.

## Acceptance criteria

- [ ] After grub config generation, the default boot entry is the
      Primary Kernel even when a higher-versioned Stray Kernel is
      installed.
- [ ] The stray kernel remains a selectable (non-default) menu entry.
- [ ] A fresh GRUB install boots the Primary Kernel by default.

## Blocked by

None - can start immediately.
