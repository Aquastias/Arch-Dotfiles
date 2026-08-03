Status: done

# Remove a persist directory from the Impermanence Editor

## Parent

`.scratch/guided-impermanence-editor/PRD.md` (ADR 0066)

## What to build

Make the persist-directory rows in the Impermanence Editor removable, turning
the write-only persist list into a managed one (like sysctl pairs and data
pools).

Pressing Enter on a persist-directory row drops exactly that entry from
`persist.directories` and re-renders the editor; the enabled state and the other
entries are untouched. Removal is **direct** — no confirmation prompt — because
it only edits Config State (nothing on disk) and is trivially re-addable,
matching the sysctl / data-pool removers.

Add a pure `edit_remove_persist` edit mirroring `edit_append_persist`:
given the config state and a directory string, remove that entry from
`persist.directories`; leave the state unchanged (rc 1) when the entry is absent
or the input is empty; leave a clean empty/absent list when the last entry is
removed.

## Acceptance criteria

- [ ] `edit_remove_persist` removes a directory from `persist.directories`.
- [ ] `edit_remove_persist` is a no-op (rc 1, unchanged) on an absent entry
      or empty input.
- [ ] Removing the last persist directory leaves an empty or absent list,
      consistent with how `edit_append_persist` seeds it.
- [ ] In the Impermanence Editor, Enter on a persist-directory row removes
      that directory and re-renders the editor.
- [ ] Removal leaves `options.impermanence.enabled` and other persist entries
      unchanged.
- [ ] Removal is direct (no confirmation prompt).
- [ ] Pure-edit bats cover `edit_remove_persist` (remove, no-op, last-entry),
      modelled on the existing `edit_append_persist` tests; controller-seam bats
      cover the Enter-to-remove behaviour and re-render.

## Blocked by

- Ticket 01 — "Collapse impermanence + persist into one Impermanence Editor"
  (`issues/01-collapse-impermanence-editor.md`). The editor screen and its
  persist-directory rows must exist first.
