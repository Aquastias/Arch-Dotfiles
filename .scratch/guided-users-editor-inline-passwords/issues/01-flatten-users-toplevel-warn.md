# Flatten Users screen + top-level password warning

Status: done (283188e)
Type: AFK

## Parent

`.scratch/guided-users-editor-inline-passwords/PRD.md` (ADR 0051).

## What to build

Collapse the Users Configuration Category so that entering `Users` lands
**directly** on the user list instead of an intermediate `users: aquastias` row.
The landed screen shows, in order: a `root password: (set|not set)` row, one row
per user rendered `name — shell · pw <ok|⚠>` when enabled and `name — disabled`
when excluded (no `[x]/[ ]` checkbox), a `＋ Create user` action, and `← Back`.

Fold a `⚠ N pw needed` marker onto the top-screen `Users` category row, where N =
root (if unset) plus each enabled user lacking a password, computed from the same
completeness predicate that drives the in-menu Proceed gate. While N > 0, the top
`Proceed` row reads as blocked (e.g. `Proceed ▸ set passwords first ⚠`); the
existing Proceed gate (notice + bell, no accept) is unchanged.

Password capture is untouched in this slice — the root and user password rows
still drop to the existing `execute()` masked prompt. Enter on a user keeps the
current enable/exclude toggle for now (the editor arrives in slice 02).

## Acceptance criteria

- [ ] Entering `Users` renders the list directly; no `users:` single-row screen.
- [ ] Root password row is the first row and shows `(set)` / `(not set)`.
- [ ] Enabled users render `name — shell · pw <ok|⚠>`; disabled render
      `name — disabled`; no checkbox glyphs.
- [ ] The top `Users` category row shows `⚠ N pw needed` with the correct count,
      and clears to no `⚠` when all required passwords are set.
- [ ] The top `Proceed` row renders blocked while N > 0 and normal when N = 0.
- [ ] The list `⚠`, the top-level count, and the Proceed gate all derive from the
      one completeness predicate over the same effective user set.
- [ ] Controller-seam bats cover the rendering + fold; no fzf glue is unit-tested.

## Blocked by

None - can start immediately.
