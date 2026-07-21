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

- [ ] `matrix.sh smoke` runs the four curated cells via `emit`/`run`
- [ ] Encrypted cell unlocks headless via the Console Answerer (no
      install-only carve-out)
- [ ] Impermanence cell asserts `verify.rollback`
- [ ] Driver exits non-zero if any cell fails; per-cell PASS/FAIL/SKIP
      summary printed
- [ ] Curated set run to green in KVM via detached `systemd-run`
      (INSTALLER-EXIT-0 + first-boot sentinel per cell)
- [ ] Usage/help updated; no git-hook/CI wiring; `matrix.sh gen` records
      unchanged
- [ ] `tests/matrix/*` and `tests/run.sh` pass

## Blocked by

None - can start immediately (independent of the validator slices).
