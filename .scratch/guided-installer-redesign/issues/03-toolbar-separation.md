# Toolbar separation (keybinds + terminal-action rows)

Status: done

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

- [x] Proceed / Save / Export are divider-separated rows, visually distinct
      from the category rows.
- [x] `^Z` undoes / `^Y` redoes over the snapshot stack; `^R` offers reset
      (field / section / all); the header advertises the keybinds.
- [x] Undo/Redo are inert when the stack has nothing to undo/redo.
- [x] The old selectable Undo / Redo / Reset footer rows are gone.
- [x] Stubbed-fzf loop bats cover keybind dispatch (prior art
      `tests/config/guided-shell.bats`); full suite green.

## Blocked by

- `.scratch/guided-installer-redesign/issues/02-two-level-category-menu.md`

## Comments

**DONE via /tdd (2026-06-21).** Toolbar pulled out of the top category list.

Render (`lib/guided.sh`): new pure `_guided_top_menu_lines <o> [<b>]` = the 8
category rows + a `_GUIDED_DIVIDER` rule + the terminal rows (Proceed / Save /
Export). The edit-history rows are gone — `_guided_footer_lines` and
`_guided_reset_lines` are **deleted** (their selectable Undo/Redo/Reset rows
no longer exist).

Keybinds: `_guided_menu_loop` now drives fzf with
`--expect=ctrl-z,ctrl-y,ctrl-r` and a `--header` (`_GUIDED_TOP_HEADER` —
"^Z undo · ^Y redo · ^R reset · Enter select · Esc cancel"). fzf prints the
pressed key on output line 1 (empty for Enter) + the selection on line 2; the
loop reads both. `^Z`→`hist_undo`, `^Y`→`hist_redo` (both already inert when
the stack has no past/future — pressing on an empty stack is a no-op),
`^R`→ new `_guided_reset_action` (a `guided_select reset_scope` picker →
field / section / all, routing to the existing `_guided_reset_field_action` /
`_guided_reset_section_action` / new `_guided_reset_all_action`). The Enter
path dispatches the divider (inert), Proceed/Save/Export, and category drill-in
exactly as before.

Test seam: `fzf_queue` stub upgraded to **emulate `--expect`** — it detects the
flag and emits a key line + selection line; a queued `ctrl-*` entry scripts that
keybind press (Enter entries stay single rows; the sub-loop, which has no
`--expect`, still gets one line). The stub also records fzf's args to
`$TEST_DIR/fzf_args` so a test asserts the `--expect` flag + header keybind
advertisement. Rewrote the row-based Undo/Reset-all/field/section loop tests to
keybinds; added `^Y` redo, `^Z`-inert, and the header tests; dropped the 3
`_guided_footer_lines` + 1 `_guided_reset_lines` tests.

`guided-shell.bats` = 78. **Full suite 1264 bats, 0 failures; shellcheck clean**
(--severity=warning; the 2 SC2153 infos are pre-existing, untouched files).
The live fzf draw (header/--expect rendering) stays smoke-only. Issue 03 was
blocked by 02 (the two-level loop) — both now done in this session.
