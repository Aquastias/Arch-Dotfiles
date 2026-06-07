# ADR 0033: Disk Wipe module extraction and pure prior-state decision

## Status
Accepted

## Context
`02-wipe.sh` fused orchestration with logic: it carried the device-aware
wipe (ZFS/LVM/MD teardown, `blkdiscard`-vs-`dd` routing, parallel
per-disk progress) inline, and the "is this disk already blank vs. does
it carry signatures" decision was welded into `is_disk_zeroed()`, which
both probed the block device (wipefs / lsblk / dd sampling) and decided.
The decision was therefore not testable without a real disk.

This ADR records the deepening slice of the lib-taxonomy-refactor (PRD:
`.scratch/lib-taxonomy-refactor`, issue 08), which thins `02-wipe.sh` to
an orchestrator and extracts the decidable part as a pure module.

The two Disk Wipe safety invariants are unchanged and must stay exact:

- The live medium is never listed, selectable, or wipeable — detected by
  multiple signals (boot-mount parent disk, `iso9660` / `ARCH_*` label),
  never by string-matching (the Live-Medium Detector, `lib/live-medium.sh`).
- An install-driven wipe touches only the install's resolved target set
  (`os_pool` + `storage_groups` + `data_pools`, resolved by the Target
  Resolver `lib/wipe/targets.sh` and passed in explicitly).

## Decision
Split probing (I/O) from deciding (pure), and move the device-aware
execution behind the `lib/wipe/` interface:

- **`lib/wipe/prior-state.sh` (new, pure).** `wipe_disk_dirty SIG NPARTS
  NONZERO` decides dirty (needs wipe) vs. blank from one disk's probed
  facts. `wipe_select_to_wipe` reads `|`-separated facts on stdin
  (`disk|is_live|sig|nparts|nonzero`) and emits the set to wipe — dirty
  AND not the live medium — in input order. No block-device access, so
  the decision is unit-testable.
- **`02-wipe.sh` keeps the probe (`_wipe_probe_disk`, I/O) and feeds the
  facts to the pure decider** via `skip_zeroed_disks`. The probe is the
  former `is_disk_zeroed` body minus its decision.
- **`lib/wipe/execute.sh` (new, I/O).** The device-aware execution
  (`teardown_zfs/lvm/mdraid`, `wipe_one_disk`, `run_parallel_wipe`) moves
  here; `02-wipe.sh` sources it and calls `run_parallel_wipe`. This is
  block-device I/O, covered by the VM smoke tests, not unit-tested.
- **The hard guard runs before the prior-state filter.** `main()` calls
  `assert_no_live_medium_targets` (loud abort) before `skip_zeroed_disks`,
  so a live target aborts loudly rather than being silently dropped. The
  live-medium fold inside `wipe_select_to_wipe` is belt-and-suspenders.

The fact delimiter is `|` (non-whitespace) so an empty `sig` field is
preserved; a tab/space would collapse runs and shift the columns.

Public-name note: `lib/wipe/prior-state.sh` (prior *disk* state) is a
different concept from `02-wipe.sh`'s `wipe_prior_state_present` (the
leftover /mnt *install* environment). The latter's tests were renamed
`tests/wipe-prior-install-state.bats` to disambiguate; no identifier
changed.

## Considered alternatives
- **Keep `is_disk_zeroed` as probe+decide.** Status quo; the decision
  stays untestable without a real disk. Rejected.
- **Pass raw `wipefs` output as the `sig` fact.** Multi-line and
  unbounded, it breaks line-based parsing. Rejected in favour of a
  presence token.
- **Let `wipe_select_to_wipe` be the only live-medium exclusion.** Drops
  a live target silently instead of aborting. Rejected; the loud hard
  guard stays the primary, the fold is defense-in-depth.
- **Leave `run_parallel_wipe` in `02-wipe.sh`.** Leaves "parallel
  per-disk progress" — device-aware behavior — outside the module.
  Rejected; the executor owns it.

## Consequences
- "Which disks need wiping" is decided by a pure function with direct
  unit tests (`tests/wipe/wipe-prior-state.bats`): no-signature → blank;
  signature / partition table / non-zero sample → dirty; the set excludes
  the live medium.
- `02-wipe.sh` reads as an orchestrator: resolve targets → guard → probe
  → decide → execute. Device-aware logic lives in `lib/wipe/`.
- The real wipe path (teardown, blkdiscard/dd, parallel progress) stays
  covered by the VM smoke tests, not unit tests — the I/O boundary is the
  test boundary.
- Behavior is preserved: the full bats suite and `audit.sh` pass
  unchanged; only `source` lines and call ordering moved.
