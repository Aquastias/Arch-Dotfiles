# Non-destructive navigation: Reset + Undo/Redo

Status: done

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

The "go back and forth without losing changes" machinery on top of the
Config State. **Reset** at three granularities — field, section, all
(Reset-all confirms first) — implemented as deletion from the sparse
override map. An **Undo/Redo** snapshot stack where every mutating action
(field edit, reset, list add/remove) is exactly one step, **including
Reset-all**; a fresh edit after an undo clears the redo stack. The fzf
shell surfaces the next Undo/Redo target and Reset-all in the footer,
marks overridden rows with `●`, and pre-marks prior picks on
multi-select re-entry.

## Acceptance criteria

- [x] `reset(field)` clears one override; `reset(section)` drops that
      subtree; `reset(all)` returns to fresh-launch state and confirms
      first.
- [x] `undo` restores the prior state; `redo` re-applies; a new edit
      after undo clears the redo stack; Reset-all is itself undoable.
- [x] Footer shows the next undo/redo target + Reset-all; `●` marks rows
      that differ from default; multi-select re-entry pre-marks prior
      picks from the state. (Pre-mark deferred to 06/07 — no multi-select
      field exists in the menu yet.)
- [x] bats: edit-sequence → state assertions, reset at each level, and
      undo/redo including undo-of-Reset-all.

## Blocked by

- `01-guided-install-tracer-bullet`

## Comments

Done via /tdd (2026-06-16). Pure core: new `lib/config/history.sh` —
past/present/future snapshot stack (`hist_new/present/commit/undo/redo/
can_undo/can_redo`), one commit = one undo step, fresh commit clears redo,
Reset-all = commit of the seeded baseline (so undoable). Reset granularities
reuse the existing `cfgstate_unset` (leaf = field, prefix = section subtree)
and `cfgstate_new` (all) — locked with bats, no new verb.

Shell (`lib/guided.sh`): `_guided_menu_loop` seeds the stack from the launch
state, commits every edit, dispatches Undo/Redo/Reset-all, and appends the
pure `_guided_footer_lines` (Undo/Redo offered only when available, Reset-all
always). Reset-all confirms via typed `RESET` through `guided_prompt`.
`_guided_edit_hostname && _guided_commit` skips the snapshot on empty input.

Interactive field/section reset wired too: `_guided_reset_lines` surfaces
"Reset field…" / "Reset section…" only when overrides exist; the actions pick
a field/section via `guided_select` and clear it in one undoable commit.
`_guided_reset_section` (pure) clears a *menu* section's rows, so the seeded
identity (locale/timezone/keymap — not rows) survives a Host reset.

Tests: `tests/config/guided-history.bats` (6), +3 reset-granularity in
`guided-state.bats`, +9 in `guided-shell.bats` (footer ×3, loop Undo,
Reset-all confirmed/declined, reset field/section pure ×2 + loop ×2). Full
`.os` suite 1092 green; shellcheck clean. Multi-select pre-marking deferred
to issues 06/07 (no multi-select field in the menu yet) — user-approved scope.
