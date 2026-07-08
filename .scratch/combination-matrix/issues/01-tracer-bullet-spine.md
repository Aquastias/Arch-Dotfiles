# 01 — Tracer-bullet spine: one cell, end-to-end

Status: done
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

- [x] `matrix.sh gen` prints a one-cell manifest line (cell-id + axis
      assignment) to stdout.
- [x] A bats test assembles the cell and asserts a clean
      `validate_install_context` (prior art: `install-print-config.bats`).
- [x] `matrix.sh emit <cell-id>` writes a valid VM Profile to tmpfs that
      `vm.sh` accepts (validates against the profile schema).
- [x] `matrix.sh run` installs the single cell in a VM and the run reports
      PASS on `INSTALLER-EXIT-0` + `===FIRSTBOOT-OK===`.
- [x] Full existing bats suite stays green.

## Blocked by

None - can start immediately.

## Comments

**Done 2026-07-08 (TDD, LOCAL/UNPUSHED).** Vertical slices:

- `tools/matrix.sh` (gen/emit/run) + sourced libs `lib/matrix/{cells,assemble,
  profile,run}.sh`. gen emits the one tracer cell `zfs-single-plain` as JSONL.
- Tier-1 (`tests/matrix/matrix-assembly.bats`): cell → `cfgstate_seed_defaults`
  + axis overrides → `emit_effective` → the REAL `validate_install_context`
  (03's module stack) passes. Prior art followed.
- emit → schema-valid VM Profile in tmpfs; `.install` = the assembled Effective
  Config (config seam). `vm.sh` accepts an absolute-path profile (new seam).
- run: co-hosted `git daemon` (local HEAD) + `vm.sh --testing --verify-boot`.
  **Live VM: `INSTALLER-EXIT-0` + `FIRSTBOOT-OK`** (guest cloned installer from
  the local daemon — `upload-pack for /.dotfiles` — proving the seam). Forced
  `ISO_URL_OVERRIDE=archlinux-2026.07.01` because the archzfs resolver has no
  ISO for the live kernel (upstream lag); ZFS installed via DKMS fallback.

**Refactor (behaviour-preserving):** promoted the disk-existence probe to a
single `_layout_disk_exists` seam in `lib/layout/core.sh`; routed the inline
`[[ -b ]]` sites in zfs/single, nonzfs/root, btrfs/multi through it and dropped
multi's duplicate. Tier-1 bats stubs it (disk existence is a Tier-2/VM concern).
Layout suite 150/150.

Suites: matrix 7/7, layout 150/150, no NEW reds. Pre-existing (clean-HEAD)
reds unrelated: `guided-shell.bats` tests 20/22 (stale "other filesystems are
reserved" — contradicted by the all-adapters-built reality).
