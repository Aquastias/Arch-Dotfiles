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
- [x] **Live KVM run GREEN — all four cells install + boot-verify.** Ran
      `ISO_URL_OVERRIDE=<2026.07.01 archive ISO> MATRIX_MAX_PARALLEL=1
      matrix.sh smoke` (~1h38m serial). Console sentinels per cell —
      `zfs-single-plain`, `zfs-mirror-plain`, `zfs-single-plain-imp`,
      `zfs-single-enc` → each `INSTALLER-EXIT-0` + `FIRSTBOOT-OK`. The
      **encrypted cell boot-verified headless** via the Console Answerer (no
      `ENCRYPTED-BOOT-FAIL`, no install-only carve-out). Two environment
      gotchas: (1) the iso-resolver returns empty on kernel 7.1 (archzfs
      prebuilt lag) — pin a cached archive ISO; the installer builds ZFS via
      DKMS from source. (2) the RAM guard oversubscribed (3×8 GB VMs on 15 GB
      free — its MemAvailable check races QEMU's lazy allocation); force
      `MATRIX_MAX_PARALLEL=1` on a RAM-tight host.
- [x] **Fixed a pre-existing driver bug the live run surfaced:** in
      `_matrix_run_one` the VM launch's verbose stdout leaked into the per-cell
      result JSON, so the summary `jq` choked (`Invalid numeric literal`) and
      the run exited 5 despite every cell passing — affects `matrix_run_all`
      too. Redirected the launch's stdout to stderr; added a regression
      (`smoke: VM stdout does not pollute the result summary`).
- [x] Usage/help updated; no git-hook/CI wiring; no `matrix_records` /
      manifest / coverage touched (`matrix.sh gen` output unchanged).
- [x] `tests/matrix/*` (12/12) and `tests/run.sh` (1857, 0 fail) pass.

## Blocked by

None - can start immediately (independent of the validator slices).
