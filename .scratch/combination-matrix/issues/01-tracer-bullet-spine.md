# 01 — Tracer-bullet spine: one cell, end-to-end

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/combination-matrix/PRD.md`

## What to build

Stand up `.os/tools/matrix.sh` as the single entry point with the three
subcommands stubbed (`gen` / `emit <cell-id>` / `run`), and drive **one
hardcoded cell** through the entire pipe end-to-end:

1. `gen` emits a one-line manifest for a single, simplest cell (e.g. zfs root,
   single disk, unencrypted, no desktop).
2. Tier-1 path: assemble that cell into an Effective Config (reusing the Guided
   assembler) and run `validate_install_context` on it.
3. `emit <cell-id>` materializes that cell to an ephemeral VM Profile in tmpfs
   (disks/verify/timeout can be minimal/fixed for now).
4. Tier-2 path: `run` installs the emitted profile via the existing config seam
   (`vm.sh --testing --verify-boot`) and asserts `INSTALLER-EXIT-0` +
   first-boot sentinel.

The point is a complete vertical slice with a single cell — no axis fan-out, no
pairwise, no registry yet. Establishes the skeleton every later slice extends.

## Acceptance criteria

- [ ] `matrix.sh gen` prints a one-cell manifest line (cell-id + axis
      assignment) to stdout.
- [ ] A bats test assembles the cell and asserts a clean
      `validate_install_context` (prior art: `install-print-config.bats`).
- [ ] `matrix.sh emit <cell-id>` writes a valid VM Profile to tmpfs that
      `vm.sh` accepts (validates against the profile schema).
- [ ] `matrix.sh run` installs the single cell in a VM and the run reports
      PASS on `INSTALLER-EXIT-0` + `===FIRSTBOOT-OK===`.
- [ ] Full existing bats suite stays green.

## Blocked by

None - can start immediately.
