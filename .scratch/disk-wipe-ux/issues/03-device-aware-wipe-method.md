# Device-aware wipe method (blkdiscard/dd) + already-zeroed skip

Status: done

## Parent

`.scratch/disk-wipe-ux/PRD.md`

## What to build

Replace the unconditional full `dd` zero-fill with a **Wipe-Method
Selector** that routes by device type: `blkdiscard` for SSD/NVMe
(near-instant, no flash wear) and a single `dd` zero-pass for HDDs.
`shred`/secure-erase is never selected — the purpose is make-blank. The
already-zeroed skip is retained so an HDD that is already blank isn't
needlessly zero-filled (moot for SSDs, since discard is instant).

## Acceptance criteria

- [x] An SSD/NVMe target is cleared via `blkdiscard`; an HDD via a single
      `dd` zero-pass.
- [x] `shred` is never used.
- [x] An already-blank disk is skipped.
- [x] The Wipe-Method Selector is unit-tested (SSD, NVMe, HDD → expected
      method).

## Blocked by

- `issues/01-live-medium-exclusion.md`
