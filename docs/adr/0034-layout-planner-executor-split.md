# ADR 0034: Layout planner/executor split and the leftover-disk seam

## Status
Accepted

## Context
The Layout Module fused planning (decidable up front) with destructive
execution. `layout_plan` lived twice — once in `single.sh`, once in
`multi.sh` — each wrapping mode-specific resolution, and the ESP
partition paths were only published by `layout_partition`, after a real
disk had been partitioned. So "what will be partitioned" could not be
asserted by a test without a block device, and the install-time
leftover-disk prompt (`pick_option` / `_read_tty`) sat inline in the
multi planner, making the planner depend on a TTY.

This ADR records the deepening slice of the lib-taxonomy-refactor (PRD:
`.scratch/lib-taxonomy-refactor`, issue 09). It preserves the phase
lifecycle (ADR 0016) and adapter-owns-validation (ADR 0014); only the
plan seam moves and the ESP timing changes.

## Decision
Split the pure planner from the destructive executor:

- **One unified `layout_plan` in `lib/layout/plan.sh`.** It brackets the
  `plan` phase, dispatches to the active mode adapter's `_layout_plan_mode`
  hook, resolves the ESP partitions, and verifies the plan contract. The
  destructive verbs (`layout_partition`, `layout_create_pools`,
  `layout_mount_esp`) and `layout_validate` stay in the mode adapters.
- **Mode-private state stays in the adapters.** `single.sh` / `multi.sh`
  keep their `_LAYOUT_IMPL_*` globals and resolution helpers; they expose
  two hooks to the unified planner: `_layout_plan_mode` (mode-specific
  record + private state) and `_layout_os_disks` (the ordered OS disks).
- **ESP paths are resolved at plan time.** `_layout_resolve_esp_parts`
  fills `LAYOUT_ESP_PARTS` from `_layout_os_disks` via `part_name`, a pure
  string transform — primary at index 0. `layout_partition` now only
  creates and formats those partitions; it no longer publishes the
  record. The plan contract asserts `LAYOUT_ESP_PARTS ≥ 1`.
- **The leftover-disk prompt is isolated behind a named adapter.**
  `layout_leftover_choice` (fold vs. own) and `layout_leftover_pool_name`
  are the seam. The default adapter is interactive (wrapping the existing
  `pick_option` / `_prompt_pool_name`); tests substitute a non-interactive
  one. `resolve_leftover_disks` calls the adapter instead of prompting
  directly, so the planner is TTY-free.

`lib/layout/common.sh` sources `plan.sh` (after the phase/contract
helpers) and both adapters source `common.sh`, so the active adapter's
hooks override the abort-by-default stubs in `plan.sh`. `03-install.sh`
is unchanged — it still calls `layout_plan`, now resolved from `plan.sh`.

## Considered alternatives
- **Keep per-mode `layout_plan` in each adapter; only add ESP + a seam.**
  Lower churn, but leaves the plan verb duplicated and the "planner" an
  adapter concept rather than a module. Rejected in favour of one
  unified, separately-testable planner.
- **Move all planning logic (topology/sizing) into `plan.sh` too.**
  Would drag the mode-private `_LAYOUT_IMPL_*` state across the seam,
  which the refactor explicitly keeps in the adapters. Rejected; only the
  `layout_plan` verb unifies, dispatching to per-mode hooks.
- **Leave ESP resolution in `layout_partition`.** Fails the goal of a
  plan that fully describes the layout before any disk is touched, and
  keeps ESP ordering untestable without partitioning. Rejected.
- **Relocate the leftover prompt to the picker.** Rejected by the PRD in
  favour of the in-planner adapter seam.

## Consequences
- `layout_plan` emits the whole normalized record — `LAYOUT_ESP_PARTS`
  (primary at index 0), `LAYOUT_OS_POOL_NAME`, `LAYOUT_DATA_POOL_NAMES`
  — and is unit-testable per mode without partitioning a disk
  (`tests/layout/layout-single.bats`, `layout-multi.bats`).
- The leftover-disk decision is testable through a substituted adapter: a
  seam test drives the planner with no TTY and asserts the adapter's
  choice flows into the record.
- The phase ordering validate→plan→partition→pools→esp is unchanged; the
  plan contract now also guarantees the ESP set.
- Behavior is preserved: the full bats suite, `audit.sh`, and the static
  shellcheck baseline pass; real partitioning/pool creation stays covered
  by the VM smoke tests.
- Historical ADRs are not rewritten; this continues numbering from 0033.
