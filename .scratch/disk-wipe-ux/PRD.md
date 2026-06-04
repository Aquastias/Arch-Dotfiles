# Disk wipe: safe selection, live-medium protection, progress bars

Status: done

Glossary: Disk Wipe, Single Entry Point, Install Config, Standalone Data
Pool, Storage Group.

## Problem Statement

The wipe step is unsafe and opaque. It wipes every detected disk by
default — you can only *exclude* by index — which on a multi-disk
machine risks erasing the data disks you wanted to keep. The live USB
running the installer can appear in the list and be wiped (its
detection is string-based and breaks on label sources and `copytoram`
boots). There is no real progress, just a 5 s text ticker, so a
multi-hour HDD wipe looks frozen. And it always performs a full `dd`
zero-fill, even on SSDs where that is slow, pointless, and wears the
drive.

## Solution

The wipe becomes an explicit **make-blank** step you opt into. Run
standalone, you choose exactly which disk(s) to wipe and the default is
*nothing*. Run by the installer, it wipes only the disks the install
will actually use. The live medium is never listed, selectable, or
wipeable. The method is device-aware: an instant `blkdiscard` on
SSD/NVMe, and a single zero-pass on HDDs shown with a real per-disk
progress bar. `shred` is not used.

## User Stories

1. As an operator, I want to pick exactly which disk(s) to wipe, so that
   I can wipe a single disk without touching the others.
2. As an operator, I want nothing wiped by default, so that I never
   destroy a disk just by pressing Enter.
3. As a person with data disks, I want an unattended install to wipe
   only the disks it will use, so that my other disks are never erased.
4. As an operator, I want the live USB never listed as wipeable, so that
   I can't accidentally erase the installer medium.
5. As an operator, I want the wipe to refuse a live-medium disk even if
   it is somehow selected, so that a mistake can't brick my boot stick.
6. As an operator on a `copytoram` boot, I want the live USB excluded
   even though it is unmounted, so that protection doesn't depend on it
   being mounted.
7. As an operator wiping an SSD/NVMe, I want an instant `blkdiscard`, so
   that I'm not waiting hours or wearing the drive.
8. As an operator wiping an HDD, I want a real per-disk progress bar with
   percent, rate, and ETA, so that I can see it's working and how long
   it will take.
9. As an operator wiping several HDDs, I want them wiped in parallel, so
   that total time is the slowest disk, not the sum.
10. As an operator, I want an already-blank disk skipped, so that I don't
    redo a multi-hour zero-fill.
11. As an operator, I want `shred` not used, so that I'm not paying for a
    forensic multi-pass erase I don't need for an install.
12. As an operator, I want a clear final confirmation before any wipe, so
    that the destructive step is always deliberate.
13. As the installer, I want to pass the target disks explicitly to the
    wipe, so that the wipe stays config-agnostic.
14. As a maintainer, I want live-medium detection isolated in a pure
    module with injectable inputs, so that I can test every signal
    without a real USB.
15. As a maintainer, I want method selection isolated and pure, so that
    SSD/NVMe/HDD routing is unit-tested.

## Implementation Decisions

- **Live-Medium Detector (deep, pure with injectable seams).** Returns
  the set of disks that are the live medium, from multiple signals: the
  parent disk of the boot mount (resolved via the kernel parent, not
  string-stripping), plus any disk carrying an `iso9660` partition or an
  `ARCH_*` archiso label. Follows the existing injectable-seam pattern
  used for prior-install-state detection so it is testable.
- **Wipe-Method Selector (pure).** Maps a disk's attributes (rotational
  flag, transport) to a method: `blkdiscard` for SSD/NVMe, a single
  `dd` zero-pass for HDD. `shred`/secure-erase is never selected.
- **Target Resolver.** Standalone: include-based selection — show the
  table, enter the index(es) to wipe (or `all`), Enter cancels; the
  default is to wipe nothing. Install-driven: the Single Entry Point
  resolves the install's target disks (from `os_pool` + `storage_groups`
  + `data_pools`) and passes them in explicitly, so the wipe itself
  stays config-agnostic.
- **Live-medium hard guard.** Even if a live-medium disk is somehow
  targeted, the wipe aborts — a belt-and-suspenders check over the
  Detector so the boot stick can never be erased.
- **Wipe Executor (I/O).** Per-disk teardown (ZFS/LVM/MD) then
  `blkdiscard` or the `dd` zero-pass; disks run in parallel, each
  writing progress to its own log.
- **Progress Renderer (pure).** Parses `dd status=progress` bytes
  against the disk size into a per-disk bar with percent/rate/ETA;
  `blkdiscard` disks show instant completion. Rendered as a multi-line
  live display.
- **Keep the already-zeroed skip.** Spares a redundant multi-hour HDD
  zero-fill; moot for SSDs since `blkdiscard` is instant.
- **Purpose is make-blank**, not secure-erase — clear structures and
  labels so the partitioner sees a pristine disk.

## Testing Decisions

- A good test asserts the **external behavior** of the pure modules with
  injected inputs, never their internals.
- **Unit-test (bats):** the Live-Medium Detector (each signal — boot
  mount's parent disk, `iso9660`, `ARCH_*` label, and the `copytoram`
  case where nothing is mounted); the Wipe-Method Selector
  (SSD/NVMe/HDD routing); the Progress Renderer (bytes + size → bar,
  clamped at 100%).
- **Prior art:** `wipe-prior-state.bats` (injectable seams over system
  state), `commons-part-name.bats` (pure device-name mapping),
  `zfs-pools.bats` (pure decisions).
- **Integration:** the live-medium guard and method routing are covered
  by the unit tests; a full VM wipe smoke test is optional and heavier.

## Out of Scope

- Secure/forensic erase (`shred`, ATA secure-erase) — a separate concern
  and a possible distinct mode if ever needed, not the install wipe.
- A configurable wipe method or pass count.
- A `pv` dependency — progress is computed from `dd status=progress`.

## Further Notes

- The safety invariants (live medium never wiped; install-driven wipe
  scoped to target disks; make-blank not secure-erase) are recorded in
  the CONTEXT "Disk Wipe" glossary entry. No ADR — the change is
  reversible.
