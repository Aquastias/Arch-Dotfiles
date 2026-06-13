# ESP Kernel Sync PostTransaction hardening

Status: ready-for-agent

## Parent

PRD: Boot-path resilience on a small FAT ESP
(`.scratch/boot-path-resilience-small-esp/PRD.md`). See ADR 0038.

## What to build

Make the ESP Kernel Sync incapable of silently committing a broken boot
image. Introduce the ESP Kernel Sync planner deep module: given the
Kernel Selection set, the boot files present, and the ESP free space, it
returns the critical copies (Primary Kernel image, present microcode,
default initramfs), the optional copies (fallback, secondary ESPs), and
a go/no-go. The runtime hook copies each critical file via
temp-file-then-rename (a failed copy leaves the prior good image
intact), `cmp`-verifies the critical default initramfs against its
`/boot` source, sweeps orphaned `.new` temp files, and exits non-zero —
failing the pacman transaction — on any critical failure. Optional files
are best-effort and self-clean a truncated remnant. The fallback
initramfs and its boot entry are kept on a ≥1G ESP and omitted on a
smaller one; entry presence always tracks image presence.

## Acceptance criteria

- [ ] A critical copy that cannot complete (full ESP) leaves the
      previous working image in place and exits non-zero, failing the
      transaction loudly.
- [ ] The critical default initramfs on the ESP is byte-identical to its
      `/boot` source after a successful run (cmp passes).
- [ ] Orphaned `.new` temp files from a prior interrupted run are removed
      at the start of a run.
- [ ] Fallback image + entry present on a ≥1G ESP, absent on a smaller
      ESP; no fallback entry references a missing image.
- [ ] Bats cover the planner: critical/optional selection, space
      go/no-go, cmp gate, sweep decision.

## Blocked by

- Issue 03 (Extract ESP Kernel Sync + drive from Kernel Selection)
