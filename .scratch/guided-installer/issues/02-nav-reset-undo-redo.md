# Non-destructive navigation: Reset + Undo/Redo

Status: ready-for-agent

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

- [ ] `reset(field)` clears one override; `reset(section)` drops that
      subtree; `reset(all)` returns to fresh-launch state and confirms
      first.
- [ ] `undo` restores the prior state; `redo` re-applies; a new edit
      after undo clears the redo stack; Reset-all is itself undoable.
- [ ] Footer shows the next undo/redo target + Reset-all; `●` marks rows
      that differ from default; multi-select re-entry pre-marks prior
      picks from the state.
- [ ] bats: edit-sequence → state assertions, reset at each level, and
      undo/redo including undo-of-Reset-all.

## Blocked by

- `01-guided-install-tracer-bullet`
