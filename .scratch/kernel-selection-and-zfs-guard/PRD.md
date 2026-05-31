Status: done

# PRD: Kernel Selection list + ZFS Module Guard

References: ADR 0024 (extends ADR 0023).

## Problem Statement

An operator running the installer on a laptop hit an opaque abort
deep in the chroot: `mkinitcpio -P` failed with `module not found:
zfs / spl / zavl / ...` while building the rolling `linux` kernel's
preset (`7.0.10-arch1-1`), taking the whole install down after
pacstrap and most of the chroot work had already run.

Root cause: a host package list hardcoded the rolling `linux`
kernel alongside `linux-lts`, so both were installed. archzfs's
`zfs-dkms` could not build ZFS against the bleeding-edge rolling
kernel, leaving that kernel's module tree with no `zfs.ko`. Nothing
checked for this until `mkinitcpio` tripped over it, far from the
real cause and with no actionable message.

Two gaps: (1) there is no early, clear signal that a selected
kernel has no buildable ZFS module; (2) selecting a non-`lts` or an
additional kernel is not a first-class, safe choice — it only ever
happened here by accident.

## Solution

Make `options.kernel` a first-class Kernel Selection: a single
flavour token or a list of them, each mapped to its kernel package
plus headers, all installed, with `zfs-dkms` building ZFS against
each. Add a fail-fast ZFS Module Guard that, immediately after
pacstrap and before chroot configuration, verifies a loadable `zfs`
module exists for every installed kernel and aborts early with
archzfs-support guidance naming any kernel that lacks one. A
Primary Kernel (the first selected) keeps the initramfs and
bootloader logic scalar for now; full multi-kernel preset wiring is
deferred.

## User Stories

1. As an operator, I want the install to fail fast with a clear
   message when a selected kernel has no ZFS module, so that I am
   not left staring at an opaque `mkinitcpio` error.
2. As an operator, I want the failure message to name the
   unsupported kernel and point at the archzfs constraint, so that
   I know to fall back to `lts` or wait for archzfs.
3. As an operator, I want the guard to fire before the chroot
   configuration work, so that I do not wait through identity and
   bootloader steps only to fail at the end.
4. As the installer maintainer, I want `options.kernel` to accept a
   single token, so that existing scalar configs keep working
   unchanged.
5. As the installer maintainer, I want `options.kernel` to accept a
   list of tokens, so that a host can be built with more than one
   kernel.
6. As the installer maintainer, I want each token (`lts`,
   `default`, `zen`, `hardened`) mapped to its kernel package and
   matching headers in one table, so that adding a flavour is a
   one-line change.
7. As the installer maintainer, I want every selected kernel
   installed with `zfs-dkms` building against each, so that the
   installed system has ZFS for whichever kernel it boots.
8. As the installer maintainer, I want an unknown kernel token to
   abort config load, so that a typo cannot silently install the
   wrong or no kernel.
9. As the installer maintainer, I want the first selected kernel
   exposed as the scalar `KERNEL` (Primary Kernel) and the full set
   as `KERNELS`, so that chroot modules that only understand one
   kernel keep working during the interim.
10. As the installer maintainer, I want the initramfs preset and
    bootloader default derived from the Primary Kernel token
    (including `zen`/`hardened`), so that a non-`lts` primary boots.
11. As the installer maintainer, I want host package lists barred
    from hardcoding kernel packages, so that the installed kernel
    set is owned solely by `options.kernel` and the original
    regression cannot recur.
12. As the installer maintainer, I want the guard to enumerate
    target kernels from their `pkgbase` markers, so that it covers
    exactly the installed kernels with no hardcoded list.
13. As the installer maintainer, I want the guard to never attempt
    a DKMS rebuild itself, so that the real cause (archzfs lag) is
    surfaced rather than masked.
14. As the installer maintainer, I want the kernel-token-to-package
    mapping and the missing-module detection to be pure, testable
    functions, so that their behaviour is locked by bats.
15. As an operator keeping `lts`, I want zero behavioural change,
    so that the hardening is invisible on the supported path.

## Implementation Decisions

- **Kernel Selection schema.** `options.kernel` accepts a string or
  an array of flavour tokens. Tokens map: `lts`→`linux-lts`,
  `default`→`linux`, `zen`→`linux-zen`, `hardened`→`linux-hardened`,
  each with its `*-headers`. The map is a table so flavours extend
  trivially. Default is `lts`. An unknown token aborts at config
  load.
- **Accessors.** `install_config_kernel` returns the Primary Kernel
  (first token). A new `install_config_kernels` returns the ordered
  list. Both normalise the string-or-array shape.
- **Install-state.** `KERNEL` stays the scalar Primary Kernel for
  back-compat; add `KERNELS` (array) carrying the full list.
- **Package collection.** `collect_packages` loops the kernel list,
  emitting each kernel package + headers via the token map;
  `zfs-dkms` and `zfs-utils` are added exactly once regardless of
  kernel count.
- **Initramfs.** The Chroot Configuration Module derives the preset
  name and fallback target from the Primary Kernel token (handling
  all four flavours). `mkinitcpio -P` continues to build every
  installed kernel's preset; custom fallback injection and
  bootloader-default tracking remain Primary-Kernel-only (interim).
- **ZFS Module Guard.** A new host-side step runs after base-system
  install and before chroot configuration. It enumerates the
  target's installed kernels from their `pkgbase` markers and, for
  each, confirms a loadable `zfs` module via `modinfo` inside the
  target root. If any kernel lacks one it aborts (no remediation)
  with a message naming the kernel(s) and referencing the archzfs
  constraint. A pure helper returns the set of kernels missing a
  ZFS module, separate from the chroot/`error` wrapper.

## Testing Decisions

Tests assert external behaviour (inputs → outputs / abort), never
internals.

- **Kernel resolver** (extend `install-config.bats`): scalar token
  → single-element list with that primary; array → ordered list,
  primary = first; absent → `lts`; unknown token → error.
- **collect_packages expansion** (extend `packages.bats`): `lts` →
  `linux-lts` + `linux-lts-headers`; a two-token list → both kernel
  packages + both headers; `zfs-dkms` present exactly once.
- **ZFS Module Guard** (new `zfs-verify.bats`): build a temp module
  tree with `pkgbase` markers; all kernels having a ZFS module →
  empty missing-set; one kernel lacking it → that kernel returned.
  Prior art: `zfs-module.bats`, which overrides real paths with
  temp dirs (`ZFS_MODULES_DIR` / `ZFS_SRC_DIR`).

## Out of Scope

- Full multi-kernel wiring: per-kernel custom fallback presets and
  per-kernel bootloader default entries (deferred behind the
  Primary-Kernel bridge).
- Any host actually selecting more than one kernel — all hosts stay
  `lts` for now; the array path ships unused.
- End-to-end validation of `zen`/`hardened` (mapping lands, not
  exercised by a host).
- A pre-pacstrap archzfs-support pre-check; the guard catches the
  failure post-build, which is sufficient.
- The live-ISO / bootstrap kernel, which ADR 0023 governs.

## Further Notes

The immediate regression trigger (hardcoded `linux` in host package
lists) was already removed in a prior commit; this PRD adds the
guard and the first-class Kernel Selection so the class of failure
cannot recur silently. The guard message and `CONTEXT.md` both
point readers at the archzfs-Compatible ISO concept and ADR 0024.
