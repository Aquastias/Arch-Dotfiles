# Stray Kernel warn hook

Status: done

## Parent

PRD: Boot-path resilience on a small FAT ESP
(`.scratch/boot-path-resilience-small-esp/PRD.md`). See ADR 0038, ADR
0024.

## What to build

Surface a Stray Kernel (a kernel installed but not in the host's Kernel
Selection) and any kernel lacking a buildable `zfs.ko`, loudly but
non-blockingly, at upgrade time. A new "Stray Kernel detector" deep
module classifies the installed kernels against the Kernel Selection and
the kernel module trees, reusing the ZFS Module Guard's existing
`zfs.ko`-presence check. A PostTransaction pacman hook prints the
finding; it never removes a kernel or blocks the transaction. The
install-time ZFS Module Guard behavior is unchanged for the supported
lts path.

## Acceptance criteria

- [x] After an upgrade, a kernel not in Kernel Selection is reported by
      name as a Stray Kernel.
- [x] A kernel whose module tree lacks `zfs.ko` is reported.
- [x] The hook never removes a kernel and never fails the transaction.
- [x] The detector reuses the ZFS Module Guard's module-presence check
      (no second copy of that logic).
- [x] Bats cover stray and `zfs.ko`-less classification over a fixture
      module tree.

## Blocked by

None - can start immediately.

## Comments

- 2026-09-27 audit: 1ffa4cc (tests/boot/stray-kernel.bats).
