# Two-level Configuration Category menu

Status: done

## Parent

`.scratch/guided-installer-redesign/PRD.md`

## What to build

Replace the flat guided menu with a two-level menu of **Configuration
Categories**. The top level lists eight categories (Host, Disks, Options,
Environment, Packages, Security, Backup, Users), each with a one-line summary
of what it configures; Enter drills into a sub-menu of that category's
fields. A section name never repeats per row. A category row shows a `●` when
any field inside it is overridden.

Pure Menu model (M1): functions returning the ordered categories (each with
summary + aggregated `●`) and the field rows for one category. The field
display *section* is independent of the Config State path, so storage-sizing
knobs render under Disks while still writing `options.*`.

Field moves in this slice: `sysctl` → Options; `mirror_countries` +
`multilib` → Options (the Pacman section folds in); `swap` / `swap_size` /
`esp_size` display under Disks; the `dotfiles_repo` field + editor are
removed. The headless replay seam stays flat-keyed (interface unchanged).

## Acceptance criteria

- [x] Top menu shows the 8 categories with summaries; no per-row section
      prefix repetition.
- [x] Enter on a category opens its field sub-menu; Esc returns to the
      category list; edits commit on confirm, never on Esc.
- [x] A category row shows `●` iff any field within it is overridden.
- [x] sysctl, mirror countries and multilib appear under Options; swap /
      swap size / esp size appear under Disks (still emitting `options.*`).
- [x] `dotfiles_repo` is gone from the menu and the emitted config.
- [x] bats for the category model (prior art `tests/config/guided-menu.bats`)
      and a stubbed-fzf loop bats for drill-in navigation.
- [x] Existing replay path + full bats suite green; an untouched run still
      emits a valid Effective Config.

## Blocked by

None - can start immediately.

## Comments

**DONE via /tdd (2026-06-21).** M1 pure category model + field moves + the
two-level fzf drill-in loop (toolbar redesign stays for issue 03).

Pure model (`lib/config/menu.sh`): two new fns over the reused per-field row
shape. `menu_categories <override> [<baseline>]` → the eight Configuration
Categories in canonical order, each `{name, summary, overridden}`; `overridden`
folds the per-field ● (override-only) by section — no new state. `menu_category_
rows <category> <o> [<b>]` → one category's rows (filter of `menu_rows`). The
field VALUE renderer gained an object case so the new **sysctl** row renders
`k=v` pairs comma-joined.

Field moves (the `_MENU_FIELDS` table is the single source): swap / swap_size /
esp_size → **Disks** (path stays `options.*` — display section ≠ Config State
path); mirror_countries / multilib → **Options** (Pacman folds in); sysctl →
**Options** as a field row (decision: a row, so it flips the Options ●, and
selecting it runs the existing add-pair editor); system_programs → **Packages**
(decision: grouped with extra packages); post_install.security → **Security**,
post_install.backup → **Backup** (Advanced dissolves); `dotfiles_repo` row +
`_guided_edit_dotfiles_repo` editor + its loop/replay dispatch **removed** (the
back-end accessor/schema keep it — only the guided surface drops it, so an
untouched/edited guided run never emits it).

Shell (`lib/guided.sh`): `_guided_menu_loop` is now a **top category loop**
(8 categories via `_guided_category_top_lines` "Name — summary ●" + the
terminal Proceed/Save/Export rows + the Undo/Redo/Reset footer); selecting a
category enters `_guided_category_loop <category>` — its field rows
(`_guided_category_lines`, label-only, no section prefix) plus that category's
local actions (Disks carries Disk layout / install disk / Add persist). Esc
(fzf non-zero) backs the sub-loop out to the category list with no commit; edits
still commit on confirm. `_guided_menu_lines` (flat "Section · label: value") is
replaced by the two render helpers.

Tests: `tests/config/guided-menu.bats` +14 (category model, summaries, ● fold,
the field moves, sysctl k=v render, dotfiles gone) — 34 total. `guided-shell.
bats` reworked to the two-level nav: a new `<ESC>` queue sentinel drives Esc;
the field-edit loop tests drill into their category first; added top/sub render
tests + an "Esc commits nothing" test; dropped the dotfiles_repo editor test —
77 total. **Full suite 1263 bats, 0 failures; shellcheck clean** (--severity=
warning). No VM here (issue 02 is bats-only; the redesign VM smoke is 04/05).
Unblocks issues 03 + 05.
