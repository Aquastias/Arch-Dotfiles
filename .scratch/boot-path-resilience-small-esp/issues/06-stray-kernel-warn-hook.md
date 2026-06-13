# Stray Kernel warn hook

Status: ready-for-agent

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

- [ ] After an upgrade, a kernel not in Kernel Selection is reported by
      name as a Stray Kernel.
- [ ] A kernel whose module tree lacks `zfs.ko` is reported.
- [ ] The hook never removes a kernel and never fails the transaction.
- [ ] The detector reuses the ZFS Module Guard's module-presence check
      (no second copy of that logic).
- [ ] Bats cover stray and `zfs.ko`-less classification over a fixture
      module tree.

## Blocked by

None - can start immediately.
