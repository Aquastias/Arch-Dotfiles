# Toolbar separation (keybinds + terminal-action rows)

Status: ready-for-agent

## Parent

`.scratch/guided-installer-redesign/PRD.md`

## What to build

Pull the toolbar out of the category list. The terminal destinations
(Proceed / Save / Export) render as selectable rows under a divider at the
bottom of the top category menu. The edit-history operations (Undo / Redo /
Reset field|section|all) become footer keybindings — `^Z` / `^Y` / `^R` (via
fzf `--expect`) shown in the header — dispatched by the menu loop against the
existing snapshot stack and reset verbs.

## Acceptance criteria

- [ ] Proceed / Save / Export are divider-separated rows, visually distinct
      from the category rows.
- [ ] `^Z` undoes / `^Y` redoes over the snapshot stack; `^R` offers reset
      (field / section / all); the header advertises the keybinds.
- [ ] Undo/Redo are inert when the stack has nothing to undo/redo.
- [ ] The old selectable Undo / Redo / Reset footer rows are gone.
- [ ] Stubbed-fzf loop bats cover keybind dispatch (prior art
      `tests/config/guided-shell.bats`); full suite green.

## Blocked by

- `.scratch/guided-installer-redesign/issues/02-two-level-category-menu.md`
