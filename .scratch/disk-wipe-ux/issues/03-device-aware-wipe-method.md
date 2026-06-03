# Device-aware wipe method (blkdiscard/dd) + already-zeroed skip

Status: ready-for-agent

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

- [ ] An SSD/NVMe target is cleared via `blkdiscard`; an HDD via a single
      `dd` zero-pass.
- [ ] `shred` is never used.
- [ ] An already-blank disk is skipped.
- [ ] The Wipe-Method Selector is unit-tested (SSD, NVMe, HDD → expected
      method).

## Blocked by

- `issues/01-live-medium-exclusion.md`
