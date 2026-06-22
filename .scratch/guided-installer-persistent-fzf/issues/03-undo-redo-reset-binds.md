# Undo / redo / reset as global fzf binds

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/guided-installer-persistent-fzf/PRD.md`

## What to build

Wire the existing history snapshot stack and the reset verbs
(field / section / all) as **global fzf key binds** (`^Z` / `^Y` / `^R`)
active at every depth in the persistent model, replacing the toolbar that
slice 01 left as header text only. The binds dispatch against the history
core and the reset verbs; the header advertises them.

## Acceptance criteria

- [ ] `^Z` undoes and `^Y` redoes over the snapshot stack at any menu
      depth; both inert when there is nothing to undo / redo.
- [ ] `^R` offers a reset scope (field / section / all); reset-all is
      itself undoable; all confirmed/gated as today.
- [ ] One edit = one undo step; leaving and re-entering a category never
      loses a value.
- [ ] Controller / dispatch bats cover the bind handling against the
      history core.
- [ ] The `--guided` replay path is unchanged; full suite green; shellcheck
      clean.

## Blocked by

- `.scratch/guided-installer-persistent-fzf/issues/01-spine-persistent-fzf-install.md`
