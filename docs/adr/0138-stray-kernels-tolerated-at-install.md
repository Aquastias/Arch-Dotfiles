# ADR 0138: Stray kernels tolerated at install time

## Status
Accepted. Amends ADR 0024.

## Context
ADR 0024's ZFS Module Guard aborts the install, host-side after pacstrap, if
*any* installed kernel lacks a `zfs.ko` — and `mkinitcpio -P` (chroot-side)
builds *every* installed kernel's preset, crashing on a kernel with no ZFS
module. Both enumerate kernels from their `pkgbase` markers, making no
distinction between a kernel the operator *chose* (`options.kernel`) and one
pulled in as a dependency.

That distinction turned out to matter. On an lts-only ZFS host, `wine` (in Host
Core) depends on `ntsync-autoload`, which hard-depends on the rolling `linux`
kernel. So a full rolling kernel is installed as a **Stray Kernel** — not in the
Kernel Selection — and archzfs's `zfs-dkms` cannot build ZFS against the
bleeding-edge rolling kernel. The guard then aborts the whole install on the
stray, even though the selected `linux-lts` has a working module.

This contradicts the Stray Kernel concept (ADR 0038), which already treats a
stray as boot-harmless and *warned, never fatal*: the ESP Kernel Sync mirrors
only entry-referenced kernels, systemd-boot entries name only the Primary
Kernel, and `GRUB_TOP_LEVEL` pins the Primary Kernel as default — so a stray is
never booted. Only the two *install-time* steps were unaware of the split.

## Decision
1. **The ZFS Module Guard aborts only for SELECTED kernels.**
   `zfs_verify_target_modules` now takes the Kernel Selection package bases and
   aborts only when `missing ∩ selected` is non-empty. A stray missing `zfs.ko`
   is warned (non-fatal) at install time — surfaced in `install.log`, not just
   on first boot.

2. **`mkinitcpio -P` skips stray kernels.** Before the build,
   `initcpio.sh` removes `/etc/mkinitcpio.d/<stray>.preset` for every stray, so
   `-P` builds only the selected kernels. The stray keeps its `vmlinuz` but gets
   **no initramfs** — a zfs-less initramfs cannot import a ZFS root, so building
   one is wasted work.

3. **One identification of "stray".** Both steps derive the selected set from
   `options.kernel` through the `kernel.sh` token→pkgbase table, and reuse
   `stray-kernel.sh`'s `stray_kernels` helper — the same logic the post-install
   warn hook (ADR 0038) already uses.

## Considered alternatives
**Remove the stray** (`pacman -Rdd linux`). Contradicts ADR 0038's "warned,
never removed", and orphans `ntsync-autoload`'s dependency.

**Prevent the dependency** (drop/replace `ntsync-autoload` or `wine`). It's a
hard dependency in Host Core — this means losing wine or forking a package, huge
collateral for a boot-harmless kernel.

**Build a zfs-less initramfs for the stray** (strip the zfs hook from its
preset). Useless on a ZFS-root system — the resulting initramfs cannot import
the pool — so it is wasted work with no recovery value.

**Extend the archzfs ceiling pin (ADR 0137) to the rolling `linux`.** Reverses
ADR 0024's deliberate stance that non-lts kernels may outrun archzfs, and pins a
dependency-pulled kernel the operator never selected.

## Consequences
- An lts ZFS host with wine (or anything else pulling a rolling kernel) now
  installs cleanly: the selected `linux-lts` is guaranteed a module; the stray
  `linux` is tolerated, warned, and left without an initramfs.
- The guard's fail-fast safety is unchanged for kernels the operator selected —
  a genuinely broken selected kernel still aborts early, before the opaque
  `mkinitcpio` crash ADR 0024 targeted.
- A stray keeps its `vmlinuz` and wastes some `/boot` space (unchanged from ADR
  0038); it is never bootable-into-ZFS and never the default boot.
- ADR 0024 still governs the guard's *purpose* (fail-fast on an unbuildable
  chosen kernel); this ADR narrows its *scope* to the Kernel Selection.
