Status: done

# Enforce Layout Module phase ordering at the seam

## Parent

`.scratch/layout-phase-lifecycle/PRD.md` (ADR 0016)

## What to build

Add a single ordinal phase counter and two guard helpers to
`lib/layout-common.sh`, then wrap every seam verb in both Layout
Adapters with enter/exit calls. Out-of-order invocation of a
destructive verb aborts via `error` before any `wipefs` /
`sgdisk` / `zpool create` runs. Internal layout implementations
stay untouched — the seam owns lifecycle, the implementation owns
its work.

Phase map (private to `lib/layout-common.sh`):

```
validate=1, plan=2, partition=3, pools=4, esp=5
```

Helper contract (from PRD §Implementation Decisions):

- `_layout_enter_phase <name>` — asserts
  `_LAYOUT_PHASE == ordinal(<name>) - 1`; errors otherwise.
- `_layout_exit_phase <name>` — sets
  `_LAYOUT_PHASE = ordinal(<name>)`.
- `_LAYOUT_PHASE` — initialised to 0; mutated only by these
  helpers.

Wrapper shape in each adapter (illustrative, both
`lib/layout-single.sh` and `lib/layout-multi.sh`):

```
layout_plan() {
  _layout_enter_phase plan
  calculate_single_disk_layout
  _layout_verify_plan_contract
  _layout_exit_phase plan
}
```

Existing post-condition helpers
(`_layout_verify_plan_contract`,
`_layout_verify_partition_contract`) stay where they are, called
between the body and `_layout_exit_phase`. Pre-condition role
(new helpers) and post-condition role (existing helpers) stay
distinct.

Helpers use phase **names** at call sites; the name→ordinal map
is private to `layout-common.sh`. Adding a sixth phase requires
one map entry plus the new wrapper — no other call sites change.

Single commit. The helpers + all 10 wrapper updates + tests
land together. `CONTEXT.md` already updated.

## Acceptance criteria

- [ ] `_LAYOUT_PHASE` is declared in `lib/layout-common.sh`,
      initialised to 0.
- [ ] `_layout_phase_ordinal <name>` maps phase names to
      ordinals (`validate=1`, `plan=2`, `partition=3`,
      `pools=4`, `esp=5`); unknown name errors.
- [ ] `_layout_enter_phase <name>` asserts
      `_LAYOUT_PHASE == ordinal(<name>) - 1` and errors with a
      clear out-of-order message otherwise.
- [ ] `_layout_exit_phase <name>` sets
      `_LAYOUT_PHASE = ordinal(<name>)`.
- [ ] Each of the 5 seam verbs in `lib/layout-single.sh`
      (`layout_validate`, `layout_plan`, `layout_partition`,
      `layout_create_pools`, `layout_mount_esp`) opens with
      `_layout_enter_phase <name>` and closes with
      `_layout_exit_phase <name>`.
- [ ] The same 5 seam verbs in `lib/layout-multi.sh` are
      wrapped identically.
- [ ] Existing `_layout_verify_*_contract` helpers stay in
      place and are called between the body and the exit
      helper.
- [ ] No internal implementation
      (`calculate_*`, `partition_*`, `create_*`, `mount_*`,
      `resolve_*`) is modified.
- [ ] No `LAYOUT_*` published global is modified.
- [ ] No `_LAYOUT_IMPL_*` private global is modified.
- [ ] `tests/layout-common.bats` covers: (a) fresh-state
      `_layout_enter_phase validate` succeeds; (b) entering an
      out-of-order phase fails with a recognisable error; (c)
      double-entering the same phase fails; (d) full
      sequential walk (validate→plan→partition→pools→esp)
      leaves `_LAYOUT_PHASE = 5`.
- [ ] `tests/layout-single.bats` adds one smoke test that
      runs the full chain through the seam wrappers (with
      stubbed `sgdisk` / `blockdev` / `lspci` consistent with
      existing fixtures) and asserts `_LAYOUT_PHASE = 5` at
      the end.
- [ ] `tests/layout-multi.bats` adds the same smoke test.
- [ ] Any existing test that drives a wrapper in isolation
      (e.g. calling `layout_partition` without first running
      `layout_plan`) is updated to seed `_LAYOUT_PHASE` to the
      prerequisite value in its setup.
- [ ] `shellcheck` passes on every changed file.
- [ ] Full `bats` suite passes.
- [ ] Single commit, conventional-commit style, capitalized
      after the prefix.

## Blocked by

`.scratch/layout-adapter-owns-validation/issues/01-layout-validate-refactor.md`
— `layout_validate` must exist on both adapters before the
`validate=1` phase entry has anything to wrap.

## Comments

- 2026-05-25: Landed scoped to phases 2-5 (plan/partition/pools/esp).
  `_LAYOUT_PHASE` seeded to 1; `validate=1` reserved in the ordinal map.
  When `layout-adapter-owns-validation/01` (ADR 0014) merges, change
  `_LAYOUT_PHASE=1` → `=0` and wrap `layout_validate`.
