Status: ready-for-agent

# `matrix.sh smoke` curated boot set (on-demand)

## Parent

`.scratch/installer-test-realism/PRD.md`

## What to build

A new `smoke` subcommand on `tools/matrix.sh` (ADR 0048) that runs a small
curated cell set headless through the existing ADR 0046 `emit`/`run` seam
and Console Answerer — the low-friction entry point for the boot-time
oracle. On-demand only; no git-hook or CI wiring (no CI exists). Committed
matrix records unchanged.

Curated cells (reuse the generator's cell ids where possible):

- single-zfs — `INSTALLER-EXIT-0` + first-boot sentinel
- multi-mirror — same oracle
- impermanence-single — `verify.rollback` (two-boot: ephemeral wiped,
  persistent survived)
- encrypted-single — Console Answerer unlock, same oracle as its plain
  peer

Reuse `lib/matrix/*` (cells/profile/run/driver); do not duplicate emit/run
plumbing. Honor existing timeout bands and the host-resource guard.

Fully AFK: verify by running the curated set in KVM via detached
`systemd-run --user` (the pattern already used for the matrix to dodge the
sandbox `/dev/kvm` hiding), asserting each cell's oracle from the serial
log — no human gate.

## Acceptance criteria

- [x] `matrix.sh smoke` runs the four curated cells (`zfs-single-plain`,
      `zfs-mirror-plain`, `zfs-single-plain-imp`, `zfs-single-enc`) drawn
      from the real generator through the shared guarded scheduler
      (`_matrix_orchestrate`, extracted from `matrix_run_all`).
- [x] Encrypted cell boot-verifies with no install-only carve-out:
      `matrix_cell_boot_verify` is true for `zfs-single-enc` (gpu=auto), so
      `matrix_run_classify` PASSes it via `vm.sh --verify-boot` → the Console
      Answerer unlocks it over serial (matrix issue 07). Stale "enc→SKIP"
      docstrings in driver.sh/run.sh corrected.
- [x] Impermanence cell (`zfs-single-plain-imp`) carries the `rollback`
      oracle (`verify.rollback`), via the unchanged `_matrix_run_one`.
- [x] Driver exits non-zero iff any cell FAILs; per-cell PASS/FAIL/SKIP
      summary + re-run hint printed (shared `matrix_summary_format` /
      `matrix_run_exit_code`; asserted in `matrix-smoke.bats`).
- [~] Live KVM run — LAUNCHED and proven end-to-end up to VM boot:
      preflight passed (kvm + libvirtd), all four curated cells selected from
      the real generator, profiles emitted, `boot-verify=true` on the
      encrypted cell (confirming no install-only carve-out), and the guard
      scheduled real parallel VMs (`matrix-zfs-single-{plain,enc}`,
      `matrix-zfs-mirror-plain`). **Blocked by infra, not the mechanism:** the
      iso-resolver found no archzfs-compatible ISO for the current kernel
      (`no available archived ISO matches archzfs kernels: 7.1`) — archzfs
      lags kernel 7.1, so no install ISO exists yet. This blocks the WHOLE
      archzfs VM tier, not just smoke. Re-run `matrix.sh smoke` once an
      archzfs 7.1 module / compatible ISO is published. VMs were torn down.
- [x] Usage/help updated; no git-hook/CI wiring; no `matrix_records` /
      manifest / coverage touched (`matrix.sh gen` output unchanged).
- [x] `tests/matrix/*` (12/12) and `tests/run.sh` (1857, 0 fail) pass.

## Blocked by

None - can start immediately (independent of the validator slices).
