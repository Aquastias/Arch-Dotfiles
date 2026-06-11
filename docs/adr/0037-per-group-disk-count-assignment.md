# ADR 0037: Per-group disk-count layout assignment

## Status
Accepted (not yet implemented). Extends ADR 0036 (unified profile);
relates to ADR 0027 (Standalone Data Pool topology rules) and ADR 0029
(picker layout validation).

## Context
ADR 0036 makes each `profile.jsonc` declare the full pool skeleton minus
`disks` (operator-picked at install). For single-pool hosts the picker
and the VM harness assign the picked disks to `os_pool` and stop;
per-group assignment for `storage_groups[]` / `data_pools[]` was deferred
as a follow-up. As a result a multi-data-pool host (e.g. `arch-data`:
`os_pool` topology `none` + `tank0` stripe + `tank1` mirror) cannot be
installed via `--profile` — the groups receive no disks.

The layout module *consumes* per-group disks (`resolve_data_pools` /
`resolve_storage_topologies` read `data_pools[].disks` /
`storage_groups[].disks` from the assembled config), so the disk arrays
must be populated upstream, by the picker/harness, before the install.

Two things were unresolved: (1) how many disks each declared group gets,
since a profile excludes devices; (2) `picker_assign_disks` validated
every group with `picker_validate_layout`, whose `none`/`stripe` ≥2 rule
encodes the *interactive OS-pool mode* prompt (`none` = 1 OS disk **+**
leftovers folded at install, ADR 0027), which is wrong for a data pool
whose own topology allows a 1-disk `stripe`.

## Decision
**Disk count is part of the declared layout shape.** Each `os_pool`,
`storage_groups[]`, and `data_pools[]` entry carries an integer
`disk_count` (`os_pool` topology `none`/`single` ⇒ 1). The profile still
carries no `disks`; the install populates `disks` of length `disk_count`.
A group's shape is read the same everywhere: `topology` + `disk_count`.

The operator multi-selects exactly `sum(disk_count)` disks; the picker
and the VM harness assign them to groups **in declared order**
(`os_pool`, then each `storage_groups[]`, then each `data_pools[]`), and
the picker's review screen shows the resulting per-group mapping so the
assignment is never implicit. Picking too few/many aborts with a clear
message naming the expected total.

**Two distinct validations, not one.** The per-group assignment path gets
its own pool-topology minimum check aligned with `layout_validate` and
the Standalone Data Pool rules — `stripe` ≥1, `mirror` ≥2, `raidz1` ≥3,
`raidz2` ≥4; `os_pool` `none`/`single` = 1 — applied per group and naming
the offender on failure. `picker_validate_layout` (the interactive
OS-pool *mode* prompt, where `none` means leftover-folding) is left
unchanged, so its semantics and tests do not regress.

In the unified model data pools are declared explicitly, so the
`os_pool none` + leftover-folding path (ADR 0027) is not exercised by a
profile install; `os_pool none` with `disk_count: 1` is simply the single
OS disk.

## Consequences
- The closed schema gains `os_pool.disk_count`,
  `storage_groups[].disk_count`, `data_pools[].disk_count`.
- A profile's layout becomes fully reproducible: "tank1 is a 2-disk
  mirror" is unambiguous, independent of how many disks are present.
- Minimums-only assignment (rejected) would have silently forbidden a
  non-minimal group (3-disk stripe, 4-disk mirror); an optional count
  with a min default (rejected) would have meant two mental models.
- The assignment path and the interactive OS-mode prompt now use
  separate, context-appropriate validators — the source of the
  arch-data rejection.
- `arch-data` (and any multi-data-pool host) installs via `--profile`
  and a `host_profile` VM run; closes the deferred follow-up
  (`.scratch/unified-host-profile/issues/12-...`).
