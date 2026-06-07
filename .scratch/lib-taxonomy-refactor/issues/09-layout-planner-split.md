Status: done

# Layout planner/executor split: pure layout/plan + leftover-disk seam

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md`

## What to build

Split the Layout Module's planning from its destructive execution.
Introduce a new **pure** module `lib/layout/plan.sh` where `layout_plan`
consumes resolved config and emits the normalized layout record
consumed by chroot/finalize:

- `LAYOUT_ESP_PARTS[]` (resolved ESP device paths, primary at index 0)
- `LAYOUT_OS_POOL_NAME`
- `LAYOUT_DATA_POOL_NAME` (empty when no data pool)

The destructive verbs (`layout_partition`, `layout_create_pools`,
`layout_mount_esp`) stay in the mode adapters (`single`, `multi`) behind
`layout/common`. `layout_validate` remains a pure check with no state
writes.

Isolate the interactive leftover-disk prompt (which runs at install time
today) behind an adapter seam, so the planner stays pure and a
non-interactive adapter can be substituted in tests. The default adapter
prompts at install time; the prompt is NOT relocated to the picker.

Preserve the phase lifecycle (validate→plan→partition→pools→esp,
enforced via `_layout_enter_phase` / `_layout_exit_phase`; ADR 0016) and
adapter-owns-validation (ADR 0014). Mode-private globals (`SINGLE_*`,
`MULTI_*`, etc.) stay inside the modules. Add an ADR for the
planner/executor split and the leftover-disk seam.

## Acceptance criteria

- [ ] `layout_plan` is pure — no state writes, no destructive ops, no
      TTY — and emits the normalized `LAYOUT_*` record
- [ ] `layout_validate` remains a pure check
- [ ] Leftover-disk prompt isolated behind an adapter seam; default
      adapter prompts at install time
- [ ] A non-interactive adapter is substitutable in tests
- [ ] Pure tests: single-mode and multi-mode emit the correct record
      (ESP ordering with primary at index 0, pool names, empty
      `LAYOUT_DATA_POOL_NAME` when no data pool)
- [ ] Seam test: planner produces a plan without a TTY and the adapter's
      choice flows into the plan
- [ ] Phase ordering validate→plan→partition→pools→esp preserved
- [ ] ADR added for the planner/executor split + leftover-disk seam

## Blocked by

- Issue 03 (`03-layout-folder-move.md`) — `lib/layout/` must exist first
