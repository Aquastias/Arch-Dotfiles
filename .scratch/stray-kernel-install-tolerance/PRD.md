# PRD: Stray Kernel install-time tolerance

Status: ready-for-agent

Anchored by [[ADR 0138]] (Stray kernels tolerated at install time), amending
[[ADR 0024]] (ZFS Module Guard) and building on [[ADR 0038]] (Stray Kernel).

## Problem Statement

Recreating `arch-combined` (an lts-only ZFS host) aborts after pacstrap:

```
==> ERROR: Missing 7.2.6-arch2-1 kernel headers for module zfs/2.4.4.
[ERROR] No ZFS kernel module was built for: linux.
[install.sh] aborted at line 378.
```

The aborting kernel is `linux` (rolling 7.2.6), **not** the selected
`linux-lts`. `linux` is a Stray Kernel — dragged in as a hard dependency
(`wine` → `ntsync-autoload` → `linux`), not in `options.kernel` — and archzfs's
`zfs-dkms` can't build ZFS against the bleeding-edge rolling kernel. The ZFS
Module Guard aborts on it even though the selected `linux-lts` has a working
module.

## Solution

Teach the two install-time steps the selected-vs-stray split the rest of the
system already uses. The ZFS Module Guard aborts only when a *selected* kernel
lacks `zfs.ko`; a stray missing it is warned (non-fatal). `mkinitcpio -P` skips
stray kernels by removing their presets first, so a stray gets no initramfs (a
zfs-less initramfs can't import a ZFS root anyway). The stray remains
boot-harmless exactly as ADR 0038 already guarantees (off the ESP, never the
default boot, surfaced by the post-install warn hook). The install completes.

## User Stories

1. As an operator installing an lts-only ZFS host that includes wine, I want the
   install to complete despite the rolling `linux` kernel wine drags in, so that
   a boot-harmless stray kernel doesn't abort my install.
2. As an operator, I want the ZFS Module Guard to still abort when a kernel I
   *selected* lacks `zfs.ko`, so that fail-fast safety is preserved for kernels
   I actually chose.
3. As an operator, I want a stray kernel missing `zfs.ko` surfaced in
   `install.log` (not only on first boot), so that I know it was tolerated and
   why.
4. As an operator, I don't want a useless zfs-less initramfs built for a stray
   kernel on a ZFS root, so that install time and `/boot` space aren't wasted.
5. As an operator, I want the selected `linux-lts` initramfs built exactly as
   before, so that the supported path is unchanged.
6. As a maintainer, I want the guard and `mkinitcpio` to derive "stray" from the
   same Kernel Selection + `stray_kernels` logic the warn hook uses, so there is
   one definition of a Stray Kernel.

## Implementation Decisions

- **Guard scoped to Kernel Selection.** `zfs_verify_target_modules` takes the
  selected package bases and aborts only on `missing ∩ selected`. A new pure
  helper computes that abort set. Strays missing `zfs.ko` are warned
  (non-fatal). The caller passes `options.kernel` → `kernel_pkg` bases.
- **`mkinitcpio -P` skips strays.** Before the build, remove
  `/etc/mkinitcpio.d/<stray>.preset` for every stray, so `-P` builds only
  selected kernels (keeping the existing `-P` + fallback-injection path). A new
  pure helper in `stray-kernel.sh` maps strays → preset paths.
- **Stray gets no initramfs** — its `vmlinuz` stays; it is never bootable-into-
  ZFS and never the default boot (unchanged from ADR 0038).
- **One "stray" definition** — both steps reuse `stray_kernels` and the
  `kernel.sh` token→pkgbase table.

## Testing Decisions

Good tests assert external behavior over a fixture module tree, not internals —
mirroring `zfs-verify.bats` and `stray-kernel.bats`.

- Guard: a *selected* kernel missing `zfs.ko` still aborts; a *stray* missing it
  → pass + warn; a selected miss aborts even when a stray also misses; the pure
  abort-set helper (`missing ∩ selected`).
- `mkinitcpio`: the pure stray→preset-path helper (strays only; empty when none).
- VM acceptance: a **forced-skew `arch-combined` recreation** must complete —
  one run proving *both* the archzfs LTS ceiling pin (ADR 0137; lts →
  `6.12.75`) **and** stray tolerance (the wine-pulled rolling `linux` tolerated).

## Out of Scope

- Removing the stray kernel, or preventing the `wine`→`ntsync-autoload`→`linux`
  dependency (rejected in ADR 0138).
- Extending the archzfs ceiling pin to the rolling `linux` (rejected).
- Any change to the post-install Stray Kernel warn hook, ESP Kernel Sync, or
  bootloader default-entry logic (already handle strays).

## Further Notes

The boot side already tolerates strays; this PRD only closes the two install-
time steps (guard + `mkinitcpio`) that didn't yet know the selected/stray split.
