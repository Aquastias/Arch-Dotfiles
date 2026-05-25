# ADR 0016: Layout Module enforces phase ordering at the seam

## Status
Accepted

## Context
The Layout Module's verbs (`layout_validate`, `layout_plan`,
`layout_partition`, `layout_create_pools`, `layout_mount_esp`) form
a strictly ordered chain. Each downstream verb reads state
populated by the previous one — `layout_partition` reads
`_LAYOUT_IMPL_DISK` set by `calculate_single_disk_layout`,
`layout_create_pools` reads `_LAYOUT_IMPL_OS_PART` set by
`partition_*`, and so on. Several of these verbs are destructive
(`wipefs -af`, `sgdisk --zap-all`, `_zpool_create`).

Ordering was enforced only by the call sequence in
`03-install.sh`. A caller invoking `layout_partition` without
`layout_plan` first would silently run `wipefs -af ""` and
`sgdisk` against a stale/empty path — no precondition check, no
abort.

The `_LAYOUT_IMPL_*` globals were already documented as private
("do not reference outside this module") with module-header
comments. Grep confirmed zero external readers — the seam was
honored by convention. The real friction was not the global
sealing but the phase-ordering gap on a destructive interface.

## Decision
Add a single ordinal phase counter `_LAYOUT_PHASE` and two helpers
in `lib/layout-common.sh`:

```
_layout_enter_phase <name>  # asserts _LAYOUT_PHASE == ordinal-1
_layout_exit_phase  <name>  # sets _LAYOUT_PHASE = ordinal
```

Phase names map to ordinals: `validate=1`, `plan=2`, `partition=3`,
`pools=4`, `esp=5`. Out-of-order calls abort via `error` before
any destructive operation runs.

Guards live in the **seam wrappers** of each adapter
(`layout_plan() { _layout_enter_phase plan; calculate_…;
_layout_verify_plan_contract; _layout_exit_phase plan; }`).
Internal implementations (`calculate_single_disk_layout`,
`partition_single_disk`, …) are untouched. The seam owns
lifecycle; implementations own their own work.

Existing post-condition helpers
(`_layout_verify_plan_contract`, `_layout_verify_partition_contract`)
stay separate, called between the body and `_layout_exit_phase`.
They check what the verb produced; the phase counter checks when
the verb may run. Different roles, kept distinct (consistent with
ADR-0014's separation of pre- and post-condition checks).

## Considered alternatives
- **Per-phase boolean flags** (`_LAYOUT_PLAN_DONE`, …). Rejected:
  five booleans, more verbose, allows non-linear graphs the
  domain doesn't have.
- **Guard only the destructive transitions** (`partition`,
  `pools`). Rejected: smaller blast radius but uneven; future
  destructive verb easy to forget. Total ordering is the actual
  invariant.
- **Move guards into internal implementations** (e.g.
  `calculate_single_disk_layout` checks phase itself). Rejected:
  mixes lifecycle concern into layout logic; duplicates across
  adapters.
- **Fold post-conditions into `_layout_exit_phase`** via a
  name→fn registry. Rejected: over-engineering for five phases;
  registry hides binding.
- **Seal `_LAYOUT_IMPL_*` globals behind an accessor**. Rejected:
  no external readers today (grep confirmed); cost (rewrite all
  internal call sites) buys hypothetical leak protection rather
  than fixing a real bug.

## Consequences
- `layout_partition` (and downstream destructive verbs) abort with
  a clear "must run after layout_plan" message instead of
  silently destroying state on an empty/stale disk path.
- Adding a sixth phase requires only an entry in
  `_layout_phase_ordinal` plus the new wrapper — no other call
  sites change.
- Phase guard tests live in `tests/layout-common.bats` (helper
  unit tests: out-of-order fails, double-enter fails, sequential
  succeeds) plus one smoke test per adapter asserting the chain
  reaches phase 5.
- The seam wrappers go from one-line pass-throughs to ~4 lines
  each. Acceptable: the wrapper is the right place for
  lifecycle, and 5 verbs × 2 adapters = 10 wrappers total.
