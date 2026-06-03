# Per-disk progress bars (Progress Renderer)

Status: ready-for-agent

## Parent

`.scratch/disk-wipe-ux/PRD.md`

## What to build

Replace the 5-second text ticker with a multi-line live display showing a
real per-disk progress bar. For HDD `dd` jobs, a **Progress Renderer**
turns bytes-written (from `dd status=progress`) and the disk size into a
bar with percent, rate, and ETA; `blkdiscard` jobs show instant
completion. Disks continue to wipe in parallel, each contributing one
line to the block.

## Acceptance criteria

- [ ] HDD wipes show a per-disk bar with percent/rate/ETA that advances
      to completion.
- [ ] SSD/NVMe wipes show instant completion.
- [ ] Multiple disks display as a stable multi-line block while wiping in
      parallel.
- [ ] The Progress Renderer is unit-tested (bytes + size → bar; clamps at
      100%).

## Blocked by

- `issues/03-device-aware-wipe-method.md`
