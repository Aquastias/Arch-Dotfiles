# Live-medium exclusion — multi-signal Detector + hard guard

Status: done

## Parent

`.scratch/disk-wipe-ux/PRD.md`

## What to build

Replace the fragile string-based live-disk detection with a **Live-Medium
Detector** that identifies the installer's own medium by multiple
signals: the parent disk of the boot mount (resolved via the kernel
parent, not by stripping digits), plus any disk carrying an `iso9660`
partition or an `ARCH_*` archiso label. The detected live disk(s) are
never listed or selectable in the wipe, and a hard guard at wipe time
aborts if a live-medium disk is somehow targeted. This holds even on a
`copytoram` boot where the USB is unmounted. The Detector takes its
system inputs through injectable seams so it is testable.

## Acceptance criteria

- [x] The live USB never appears in the wipe's disk list and cannot be
      selected.
- [x] Wiping aborts if a live-medium disk is targeted (belt-and-
      suspenders guard).
- [x] Exclusion works when the boot source is a label/uuid path and when
      the USB is unmounted (copytoram).
- [x] The Detector is unit-tested across each signal: boot-mount parent
      disk, `iso9660`, `ARCH_*` label, and the unmounted case.

## Blocked by

None - can start immediately.
