# Tolerate stray kernels at install time (guard + mkinitcpio)

Status: ready-for-agent

## Parent

`.scratch/stray-kernel-install-tolerance/PRD.md`

## What to build

Teach the two install-time steps the selected-vs-stray kernel split so a
boot-harmless Stray Kernel no longer aborts the install.

- The ZFS Module Guard (`zfs_verify_target_modules`) takes the Kernel Selection
  package bases and aborts only when a *selected* kernel lacks `zfs.ko`
  (`missing ∩ selected`). A stray missing `zfs.ko` is warned (non-fatal) at
  install time. The host caller passes `options.kernel` → `kernel_pkg` bases.
- `mkinitcpio -P` skips strays: before the build, remove each stray's
  `/etc/mkinitcpio.d/<stray>.preset`, so `-P` builds only selected kernels. The
  stray keeps its `vmlinuz` but gets no initramfs.
- Both derive "stray" from the same `stray_kernels` helper + the `kernel.sh`
  token→pkgbase table (one definition, reused by the post-install warn hook).

## Acceptance criteria

- [ ] Guard aborts when a kernel in `options.kernel` lacks `zfs.ko`.
- [ ] Guard passes (warns, non-fatal) when only a stray kernel lacks `zfs.ko`.
- [ ] Guard aborts on the selected kernel even when a stray is also missing.
- [ ] `mkinitcpio -P` builds selected kernels' initramfs unchanged; no initramfs
      is built for a stray (its preset is removed first).
- [ ] bats cover: the pure abort-set helper (`missing ∩ selected`), the guard's
      abort-vs-tolerate split, and the pure stray→preset-path helper.
- [ ] Existing guard/stray tests updated to the selection-aware contract.

## Blocked by

- None - can start immediately
