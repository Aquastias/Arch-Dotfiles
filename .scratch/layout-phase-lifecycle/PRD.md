Status: done

# PRD: Layout Module phase lifecycle

References: ADR 0016. Depends on ADR 0014's
`layout_validate` verb.

## Problem Statement

The Layout Module's verbs (`layout_validate`, `layout_plan`,
`layout_partition`, `layout_create_pools`, `layout_mount_esp`)
form a strictly ordered chain. Each downstream verb reads state
populated by the previous one — `layout_partition` reads the
target disk path set by `layout_plan`; `layout_create_pools`
reads the partition paths set by `layout_partition`; and so on.
Several verbs are destructive (`wipefs -af`, `sgdisk --zap-all`,
`zpool create`).

Ordering is enforced only by the call sequence in `03-install.sh`.
A caller that invokes `layout_partition` without `layout_plan`
first runs `wipefs -af ""` and `sgdisk` against a stale or empty
disk path — no precondition check, no clear abort, silent failure
or partial damage depending on what the implementation-private
globals happen to hold.

The implementation-private globals (`_LAYOUT_IMPL_*`) are
documented as private but have no enforcement; grep confirms zero
external readers today. The real friction is not hypothetical
global leakage — it is the missing lifecycle guard on a
destructive interface.

## Solution

Each Layout Adapter's seam wrapper enters and exits a tracked
phase. A single ordinal counter and two helpers in
`lib/layout-common.sh` enforce the chain. Out-of-order calls
abort via `error` before any destructive operation runs. The
seam owns lifecycle; internal implementations
(`calculate_*`, `partition_*`, …) stay untouched. Existing
post-condition helpers
(`_layout_verify_plan_contract`,
`_layout_verify_partition_contract`) remain as a separate role —
they verify what the verb produced; the new helpers verify when
the verb may run.

## User Stories

1. As an operator running the install, I want
   `layout_partition` to abort with a clear "must run after
   layout_plan" message if called out of order, so that
   `wipefs -af` never touches an empty or stale disk path.
2. As an operator running the install, I want
   `layout_create_pools` to abort cleanly if `layout_partition`
   has not run, so that `zpool create` never targets a
   non-existent partition path.
3. As an operator running the install, I want the happy path
   (validate → plan → partition → pools → esp) to behave
   identically to today, so that a correct install is observably
   unchanged.
4. As an installer maintainer, I want adding a sixth Layout
   verb to require updating one phase map in
   `lib/layout-common.sh` plus the new wrapper itself, so that
   no other call sites change.
5. As an installer maintainer, I want phase ordering to be the
   responsibility of the seam wrapper, not the internal
   implementation, so that
   `calculate_single_disk_layout` / `partition_single_disk` /
   etc. stay focused on layout work.
6. As an installer-test author, I want the phase-counter helpers
   to be tested in isolation — out-of-order fails, double-enter
   fails, sequential succeeds — so that the lifecycle invariant
   is covered without standing up an end-to-end fixture.
7. As an installer-test author, I want a smoke test per adapter
   that runs the full chain and asserts the counter lands on
   the final phase, so that I know the wrappers are correctly
   instrumented.
8. As a future engineer reading a seam wrapper, I want
   `_layout_enter_phase plan` / `_layout_exit_phase plan` to use
   phase names (not raw ordinals), so that call sites are
   self-documenting.
9. As a future engineer wondering why the wrapper has three
   calls instead of one (`enter / body / exit`), I want
   ADR 0016 to be discoverable, so that the lifecycle rationale
   is on record.

## Implementation Decisions

- **New module additions in `lib/layout-common.sh`**: a single
  ordinal counter `_LAYOUT_PHASE` (initialised to 0), a private
  `_layout_phase_ordinal <name>` mapping
  (`validate=1`, `plan=2`, `partition=3`, `pools=4`,
  `esp=5`), and two public-to-the-module helpers
  `_layout_enter_phase <name>` (asserts
  `_LAYOUT_PHASE == ordinal-1`) and
  `_layout_exit_phase <name>` (sets
  `_LAYOUT_PHASE = ordinal`).
- **Helper failure mode**: `error` (exits non-zero) — consistent
  with the rest of the Layout Module.
- **Wrappers updated in both adapters** (`lib/layout-single.sh`,
  `lib/layout-multi.sh`): each of the 5 seam functions
  (`layout_validate`, `layout_plan`, `layout_partition`,
  `layout_create_pools`, `layout_mount_esp`) gains
  `_layout_enter_phase <name>` at the top and
  `_layout_exit_phase <name>` at the bottom. Existing
  post-condition helpers
  (`_layout_verify_plan_contract`,
  `_layout_verify_partition_contract`) remain in their current
  positions, called between the body and `_layout_exit_phase`.
- **Internal implementations untouched**:
  `calculate_single_disk_layout`, `partition_single_disk`,
  `create_single_pools`, `mount_single_esp`,
  `resolve_os_topology`, `partition_os_disks_multi`, … all
  stay as-is. Lifecycle concern is at the seam, not in the
  layout logic.
- **Phase model is a single ordinal counter, not per-phase
  booleans**: chosen because the chain is genuinely linear. A
  sixth phase only requires one entry in the ordinal map.
- **Names, not numbers, at call sites**: helpers accept phase
  names; the name→ordinal map is private to
  `layout-common.sh`. Call sites stay self-documenting.
- **Pre- vs. post-condition split preserved**: the new helpers
  guard pre-conditions (when a verb may run); the existing
  `_layout_verify_*_contract` helpers guard post-conditions
  (what a verb must have produced). Distinct roles, not folded
  together.
- **No changes to the published `LAYOUT_*` output globals**.
- **No changes to the implementation-private `_LAYOUT_IMPL_*`
  globals**. The original "seal them behind an accessor"
  framing of this candidate was rejected after grep showed zero
  external readers.
- **`CONTEXT.md`** already updated to mention the phase
  lifecycle in the Layout Module entry.
- **Depends on ADR 0014's `layout_validate` verb** existing on
  both adapters. If that refactor is not yet merged, this PRD
  applies the phase guards to the four remaining verbs and
  adds the `validate` phase entry once `layout_validate` lands.

## Testing Decisions

- **What makes a good test**: drive `_layout_enter_phase` /
  `_layout_exit_phase` through their public-to-the-module
  interface with controlled `_LAYOUT_PHASE` starting values and
  assert exit status + stderr substring. For adapter-level
  tests, drive the chain through the seam wrappers with stubbed
  `sgdisk` / `blockdev` / `lspci` and assert `_LAYOUT_PHASE`
  lands on the final ordinal.
- **Modules to test**: `lib/layout-common.sh`,
  `lib/layout-single.sh`, `lib/layout-multi.sh`.
- **Test shape**:
  - Helper unit tests in `tests/layout-common.bats`:
    - Fresh state → `_layout_enter_phase validate` succeeds.
    - `_layout_enter_phase plan` from fresh state fails with a
      clear out-of-order message.
    - Calling `_layout_enter_phase plan` twice in a row fails
      (double-enter).
    - Full sequential happy path
      (validate→plan→partition→pools→esp) leaves
      `_LAYOUT_PHASE = 5`.
  - One smoke test per adapter in `tests/layout-single.bats`
    and `tests/layout-multi.bats`: run the full chain through
    the seam wrappers against the existing fixture
    `install.jsonc`, assert `_LAYOUT_PHASE` reaches 5 at the
    end. Existing per-verb tests stay as they are.
- **Prior art**: `tests/layout-single.bats` and
  `tests/layout-multi.bats` already test the seam verbs
  individually with fixtures and stubs. The smoke test reuses
  the same fixture infrastructure end-to-end.
- **Coverage parity**: no existing test should fail because of
  the new guards. If any test currently calls a wrapper
  out-of-order (e.g. tests `layout_partition` in isolation
  without first running `layout_plan`), the test must set up
  `_LAYOUT_PHASE` to the prerequisite value as part of its
  fixture.

## Out of Scope

- Sealing `_LAYOUT_IMPL_*` globals behind an accessor. Rejected
  in the grilling — no external readers today; cost (rewriting
  all internal sites) outweighs hypothetical-leak protection.
- Folding `_layout_verify_*_contract` post-conditions into
  `_layout_exit_phase` via a name→fn registry. Rejected as
  over-engineering for five phases.
- Per-phase boolean flags. Rejected because the chain is
  genuinely linear.
- Guarding only the destructive transitions. Rejected because
  total ordering is the actual invariant — uneven guards leave
  a future destructive verb easy to forget.
- Any change to internal layout implementations
  (`calculate_*`, `partition_*`, `create_*`, `mount_*`,
  `resolve_*`).
- Renaming the existing post-condition helpers.

## Further Notes

- **Single commit** — helpers + wrapper updates in both
  adapters + tests land together.
- **Wrapper size growth** — seam wrappers go from one-line
  pass-throughs to ~4 lines each. Acceptable: 5 verbs × 2
  adapters = 10 wrappers total, and the wrapper is the right
  place for lifecycle.
- **Phase ordinal `validate=1`** assumes ADR 0014's
  `layout_validate` is in place. If this PRD lands first,
  scope down to phases 2-5 and add `validate=1` when the
  ADR 0014 refactor merges.
