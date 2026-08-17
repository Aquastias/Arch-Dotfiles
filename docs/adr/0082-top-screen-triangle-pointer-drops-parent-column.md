# Top screen drops the parent-column preview for a triangle pointer

---
Status: accepted (amends ADR 0071's master-detail parent column for the top
screen; builds on ADR 0081's bucketed top list)
---

On the Guided Installer **top screen**, the preview pane no longer renders the
**Categories parent column** (the full category list with the current one marked
`▶`, ADR 0071). Instead the current selection is shown by the **fzf triangle
pointer (`▶`)** in the main list itself, and the pane shows only the highlighted
category's own detail. The top-list categories also gain a **blank spacer line
between buckets** (ADR 0081) so the now-primary list breathes.

## Why

ADR 0071 could not freeze the left column while drilling, so it reproduced the
parent list inside the preview pane. But on the top screen that pane column was a
near-verbatim copy of the main list beside it — the same fourteen categories,
twice. With ADR 0081's bucket headers the main list is already scannable, so the
duplicate is noise. Marking the current row with fzf's own pointer glyph (set to
`▶`) carries the "you are here" signal without a second rendered list, and frees
the pane to show just the highlighted category's fields.

## Scope

- **Top screen only.** `_ctl_detail_top` drops the `Categories` column and its
  `_ctl_detail_column` call; a category row previews its own `label: value`
  fields (Users still previews its account table), and a non-category row
  (Profiles / Proceed / a bucket header / a spacer) previews nothing.
- **Drill (category) screens are unchanged.** `_ctl_detail_category` keeps its
  sibling-field parent column — there the column lists the category's *fields*,
  not a copy of the main list, so it still earns its place.
- **`menu_top_lines`** emits a blank line between buckets; the fzf shell sets
  `--pointer='▶'`.

## Considered options

- **Keep the top parent column (ADR 0071 as-is).** Rejected: it duplicates the
  main list now that buckets make that list scannable.
- **Drop the parent column on every screen.** Deferred: the category screen's
  column lists fields, not categories, so it is not a duplicate; left intact.

## Consequences

- `_ctl_detail_column` remains, used only by the category screen.
- CONTEXT.md's master-detail description is updated: the top screen's current
  selection is the triangle pointer, and the pane shows only the highlighted
  item; drill screens retain their sibling column.
- The `--pointer` flag lives in the fzf interactive glue (`lib/guided.sh`),
  which is unverified by bats; the pane behaviour is covered by guided-detail
  bats.
