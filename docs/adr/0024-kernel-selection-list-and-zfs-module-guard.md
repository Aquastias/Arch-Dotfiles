# ADR 0024: Kernel selection as a flavour-token list, guarded

## Status
Accepted. Extends ADR 0023.

## Context
ADR 0023 keeps the *live ISO* on an archzfs-supported kernel. It left
implicit that the *installed system* should likewise run a kernel
archzfs can build ZFS against — in practice `linux-lts`, the only
flavour archzfs reliably tracks.

That assumption broke. A host package list hardcoded the rolling
`linux` kernel alongside `linux-lts`, so both were installed. archzfs's
`zfs-dkms` could not build ZFS against the bleeding-edge rolling kernel
(`7.0.x`), leaving `/usr/lib/modules/<rolling>/` with no `zfs.ko`. The
failure surfaced only later and opaquely, mid-`mkinitcpio -P`, as
`module not found: zfs` while building the rolling kernel's preset —
aborting the install after pacstrap and most of the chroot work.

Separately, we *want* to select non-lts and multiple kernels
deliberately, not have them leak in by accident.

## Decision
1. **`options.kernel` is a flavour-token list.** It accepts a single
   token (string) or an array. Tokens map to a kernel package plus
   matching headers: `lts`→`linux-lts`, `default`→`linux`,
   `zen`→`linux-zen`, `hardened`→`linux-hardened`. Every selected
   kernel is installed; `zfs-dkms` builds ZFS against each. The
   token→package map is a table, so adding flavours is a one-line
   change. Default remains `lts`.

2. **Primary-kernel bridge.** The first token is the Primary Kernel.
   `install-state.json` exposes the scalar `KERNEL` (primary, for
   back-compat) plus `KERNELS` (the full list). The initramfs
   preset/fallback logic and the bootloader default boot entry track
   only the Primary Kernel for now; `mkinitcpio -P` still builds every
   installed kernel's preset. Full per-kernel preset/fallback wiring is
   deferred.

3. **Fail-fast ZFS Module Guard.** Immediately after pacstrap,
   host-side, before chroot configuration begins, verify a loadable
   `zfs` module exists for every installed kernel and abort with
   archzfs-support guidance if any is missing. The check enumerates the
   target's kernels and is multi-kernel-safe by construction. No
   auto-remediation.

## Considered alternatives
**Keep scalar, lts-only (status quo).** Simplest and matches the
implicit 0023 assumption, but blocks the deliberate goal of selecting
other or multiple kernels.

**Full multi-kernel now** — per-kernel presets, fallbacks and
bootloader entries in one change. More complete but a much larger
surface; deferred behind the primary-kernel bridge so the schema and
the guard land first.

**Guard auto-remediates** (DKMS rebuild on a missing module). Hides the
real cause (archzfs lagging the chosen kernel) and adds moving parts to
the hottest install path. Fail-fast with a clear message is preferred.

**Raw package names in `options.kernel`** (`["linux-lts","linux"]`).
Most flexible, but leaks pacman names into config and loses the
"`lts` is the archzfs-safe token" semantics the guard and docs rely on.

## Consequences
- Selecting any non-lts kernel is now allowed, but the install only
  completes when archzfs supports that kernel. Otherwise the guard
  aborts early naming the unsupported kernel, instead of a mid-
  `mkinitcpio` crash.
- Secondary kernels are installed and get default presets, but not the
  custom fallback-preset injection or the bootloader default until the
  deferred preset wiring lands — recorded by the Primary Kernel term.
- Host package lists must not hardcode kernel packages: the installed
  kernel set is owned solely by `options.kernel`. That hardcoding was
  the regression that motivated this ADR.
- ADR 0023 still governs the live-ISO/bootstrap kernel; this ADR
  governs the installed-system kernel set. The two are independent.
