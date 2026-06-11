# Per-group data-pool disk assignment (picker + VM harness)

Status: needs-triage

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Close the deferred follow-up that blocks installing any multi-data-pool
host (e.g. `arch-data`) via `--profile`. Today both front-ends assign
*all* picked disks to `os_pool` and never populate `storage_groups[]` /
`data_pools[]`, so a host that declares data pools can't assemble (the
groups get 0 disks → validation fails). Surfaced verifying issue 08.

Two coupled problems:

1. **Distribution.** Neither `install.sh:_install_pick_assignment` (the
   interactive picker) nor `vm/lib/profile.sh:_profile_resolve_host` (the
   VM harness) maps picked disks onto the declared
   `os_pool` + `storage_groups[]` + `data_pools[]` groups. They emit only
   `{mode:"multi", os_pool:[...all disks...]}`. The downstream
   `picker_assign_disks` already *accepts* a per-group assignment
   (`{os_pool:[...], storage_groups:[[...]], data_pools:[[...]]}`) and
   validates each — so the gap is purely on the producing side: decide how
   many disks each group gets.

2. **Validator min-disk conflict.** `picker_assign_disks` validates each
   group via `picker_validate_layout`, whose table is `none`/`stripe` **>=2**
   (`lib/picker.sh`). But the actual layout, `layout_validate`
   (`lib/layout/multi.sh`), treats `none` as a **1-disk** OS pool and
   `stripe` as a **1-disk** "independent" alias — which is exactly what
   `arch-data` (os_pool `none`, `tank0` `stripe`) relies on. So even a
   correct per-group assignment is rejected by `picker_validate_layout`.
   These two validators must be reconciled (or the assignment path must
   validate against the layout semantics, not the picker-prompt semantics)
   without regressing the interactive picker's own min-disk tests
   (`tests/picker.bats`, `tests/picker-assign.bats`).

## Acceptance criteria

- [ ] `install.sh --profile <multi-data-pool-host>` maps picked disks onto
      every declared group (os_pool + storage_groups + data_pools),
      validated against the layout's real min-disk rules.
- [ ] `vm/lib/profile.sh:_profile_resolve_host` does the same for a VM disk
      list, so `host_profile: arch-data` assembles + installs.
- [ ] `none` (1-disk OS pool) and `stripe`/independent (1-disk data pool)
      are accepted on the assignment path; `mirror`>=2 / `raidz1`>=3 /
      `raidz2`>=4 still enforced and named per group on failure.
- [ ] Interactive-picker min-disk behaviour + its bats suite stay green
      (no regression from the reconciliation).
- [ ] `arch-data` installs end-to-end via `--profile` (or a host_profile
      VM run) with `vm-data` owning `tank0`/`tank1` — closes issue 08 AC3.

## Open questions (triage)

- How are per-group disk *counts* determined? Options: (a) the profile
  declares a per-group `disks` count; (b) the picker prompts per group;
  (c) assign each group its topology minimum in declared order (works when
  the picked total == sum of minimums). VM tests likely want (a) or (c).
- Reconcile by (i) splitting `picker_validate_layout` into a prompt-mode
  table vs a topology-min table, or (ii) routing the assignment path
  through `layout_validate`'s rules directly?

## Blocked by

- None (the loader/assembler seam `picker_assign_disks` already exists).

## Relates to

- `.scratch/unified-host-profile/issues/03-install-profile-frontend.md`
  (deferred this as the per-group follow-up).
- `.scratch/unified-host-profile/issues/08-migration-tracer-arch-data.md`
  (AC3 blocked on this).
