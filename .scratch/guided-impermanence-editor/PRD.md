# PRD: Guided Installer Impermanence Editor

Status: done
Category: enhancement
ADR: docs/adr/0066-guided-impermanence-editor.md

## Problem Statement

On the Guided Installer's **Disks** screen, impermanence is presented as two
disconnected controls: an inline `impermanence:` on/off toggle field, and — only
when it is on — a separate `Add persist directory ▸ …` action row lower on the
same screen. The operator sees them as unrelated peers even though the second is
meaningless without the first. There is also no way to see or remove a persist
directory once added; `persist.directories` can only be appended to, so a
mistaken entry can only be undone by editing the profile. The split reads as
odd and the persist list is write-only.

## Solution

Merge the two into one section, using the same collapsible drill-down pattern
the Guided Installer already uses for **Encryption** (ADR 0059) and **Swap**
(ADR 0045). The Disks screen shows a single **`Impermanence ▸ on/off`** row
(carrying the standard override `●` dot). Enter opens an **Impermanence Editor**
screen that holds the enablement toggle *and* persist-directory management
together:

- **Off** — the editor collapses to just `enabled: off`.
- **On** — `enabled: on` (Enter toggles), one row per user-added persist
  directory (Enter removes it), a read-only summary line
  `curated defaults: N paths always persisted`, and an `Add persist directory`
  action that appends to `persist.directories` and returns to the editor.

This is a menu-surface change only: the stored config shape, install-time
validation, the hybrid-GPU ban, and rollback mechanics are unchanged.

## User Stories

1. As an operator configuring a host, I want impermanence and its persist
   directories under one `Impermanence` section, so that I understand the two
   settings are related rather than seeing them as unrelated Disks-screen rows.
2. As an operator, I want a single `Impermanence ▸ on/off` row on the Disks
   screen, so that the screen stays as tidy as the Encryption and Swap rows.
3. As an operator, I want the `Impermanence ▸` row to show whether it is on or
   off at a glance, so that I read the machine's posture without drilling in.
4. As an operator who overrode the default, I want the `Impermanence ▸` row
   to carry the standard override `●` dot, so that it reads like every other
   overridden field.
5. As an operator, I want Enter on the `Impermanence ▸` row to open a dedicated
   editor screen, so that all impermanence controls are in one place.
6. As an operator with impermanence off, I want the editor to show only the
   enable toggle, so that I am not shown persist controls that would configure
   nothing.
7. As an operator, I want to toggle impermanence on/off from inside the editor,
   so that I do not need a separate top-level toggle.
8. As an operator, I want toggling impermanence back to the baseline value to
   drop the override (strict delta), so that a no-op edit does not dirty the
   config or Export.
9. As an operator with impermanence on, I want to see each persist directory I
   have added listed as its own row, so that I can review what I have declared.
10. As an operator, I want to remove a persist directory via Enter on its
    row, so that I can undo a mistaken entry without hand-editing the profile.
11. As an operator, I want persist-directory removal to take effect immediately
    without a confirmation prompt, so that it behaves like the sysctl and data
    pool removers I already use.
12. As an operator, I want an `Add persist directory` action inside the editor,
    so that I can extend the persisted set from the same section.
13. As an operator, I want adding a persist directory to return me to the
    Impermanence Editor (not the Disks screen), so that I can immediately add or
    remove more.
14. As an operator, I want a read-only line telling me a curated baseline of
    paths is always persisted, so that I understand my entries extend a default
    set rather than replacing it.
15. As an operator, I do not want the curated defaults enumerated as rows, so
    that the two paths I actually manage are not buried in a long list.
16. As an operator, I want the Impermanence Editor to manage persist
    *directories* only, so that the surface stays simple and matches today's
    behaviour.
17. As an operator, I want persist directories I have already declared to be
    retained (not deleted) when I toggle impermanence off, so that toggling off
    and on again does not lose my list.
18. As an operator, I want Esc / Back from the editor to return me to the Disks
    screen, so that navigation matches the Encryption and Swap editors.
19. As an operator on btrfs, I want the editor to behave the same as on ZFS
    without exposing ZFS-only dataset/mount internals, so that I cannot
    misconfigure filesystem-specific fields that do not apply.
20. As a maintainer, I want this to be a menu-surface change with the stored
    config shape unchanged, so that install-time validation, replay, Export, and
    Save keep working without modification.
21. As a maintainer, I want the pure logic covered by unit tests at the existing
    controller and edit seams, so that the behaviour is locked down without a
    live terminal.

## Implementation Decisions

- **New nav screen `impermanence`.** Add a `nav_to_impermanence` navigation verb
  (screen token `impermanence`, carrying the category) modelled on
  `nav_to_encryption` / `nav_to_swapedit`. `nav_back` from the `impermanence`
  screen returns to the Disks category, mirroring the other sub-editors.
- **Disks screen row.** Replace the inline `impermanence:` toggle field with a
  single `Impermanence ▸ on/off` drill-down row on the Disks category screen,
  rendered next to the existing `Encryption ▸` collapse and carrying the same
  override-dot treatment. The former standalone `Add persist directory` action
  row on the Disks screen is removed (it moves into the editor).
- **Editor render.** A new render branch for the `impermanence` screen: when the
  effective `options.impermanence.enabled` is false, emit only `enabled: off`
  row; when true, emit `enabled: on`, one row per entry in effective
  `persist.directories`, a read-only count line for the curated defaults always
  persisted (count only, from the source the persist validator already uses),
  and an `Add persist directory` action row; always a Back action.
- **Editor dispatch.** A new enter branch for the `impermanence` screen:
  the `enabled:` row flips `options.impermanence.enabled` with the same
  strict-delta normalisation the encryption/swap toggles use (landing on the
  baseline drops the override); a persist-directory row removes that directory;
  the `Add persist directory` action opens the `__persist__` text screen.
- **New pure edit `edit_remove_persist`.** Add to the edits module, mirroring
  `edit_append_persist`: given the config state and a directory string, remove
  that entry from `persist.directories`; unchanged (rc 1) when the entry is
  absent or input is empty. Removing the last entry leaves an empty/absent list,
  consistent with how the append edit seeds it.
- **`__persist__` return re-route.** The `__persist__` text-screen commit
  currently falls through to the generic "back to category" return. Add a
  dedicated case so it returns to the `impermanence` editor instead — the same
  pattern `sysctl` and `options.swap_size` already use to return to their list /
  sub-editor rather than the category.
- **Curated-defaults count.** The read-only line reports the number of curated
  persist paths already guaranteed, reusing the curated-defaults source the
  install-time persist validator already consults; it is informational only and
  Enter on it is a no-op.
- **Scope boundaries in the model.** `persist.files` and
  `options.impermanence.dataset` / `mount` are not surfaced in the editor; they
  remain file-editable with their existing defaults and validation. The editor
  never writes them.
- **No stored-shape change.** The editor reads and writes only the existing
  `options.impermanence.enabled` and `persist.directories[]` keys. No schema,
  Export, Save, replay, or back-end change.

## Testing Decisions

- **What makes a good test here:** assert on rendered screen rows and on the
  resulting Config State (external behaviour), never on internal helper calls.
  Drive the controller exactly as an fzf bind would — through `guided_ctl_list`
  (render) and `guided_ctl_enter <line> [query]` (dispatch), asserting the JSON
  the state file ends up holding — the same style the Encryption and Swap editor
  tests already use.
- **Controller seam (`guided-controller.bats`):**
  - The Disks screen renders a single `Impermanence ▸ on`/`off` row (with the
    override dot when overridden) and no longer renders a standalone
    `impermanence:` field or a Disks-level `Add persist directory` row.
  - Enter on `Impermanence ▸ …` navigates to the `impermanence` screen.
  - The editor renders only `enabled: off` when off; renders `enabled: on`, the
    persist-directory rows, the curated-defaults count line, and the add action
    when on.
  - Enter on `enabled:` flips it; toggling back to the baseline drops the
    override (strict delta).
  - Enter on a persist-directory row removes that directory and re-renders
    the editor; other entries and the enabled state are untouched.
  - The add action opens the `__persist__` text screen, and committing a
    directory appends it and returns to the `impermanence` editor.
  - Back from the editor returns to the Disks category.
  - Prior art: the `swapedit` / encryption-editor render and enter tests
    in the same file.
- **Pure-edit seam (`guided-edits.bats`):** `edit_remove_persist` drops a named
  directory, is a no-op (rc 1) on an absent entry or empty input, and leaves a
  clean empty/absent list when the last entry is removed. Prior art: existing
  `edit_append_persist` tests.

## Out of Scope

- Managing `persist.files` through the menu (stays file-editable).
- Exposing `options.impermanence.dataset` / `mount` in the menu.
- Enumerating curated-default persist paths as individual rows (count only).
- Any change to install-time persist validation, the hybrid-GPU ban,
  dataset-rollback/impermanence mechanics, Export/Save/replay, or the stored
  config schema.
- A confirmation prompt on persist-directory removal (removal is direct).

## Further Notes

- Follows ADR 0066; extends the collapsible-editor pattern of ADR 0059
  (Encryption) and ADR 0045 (Swap).
- The live drill-down is exercised by the existing PTY smoke harness the way the
  other editors are; the two bats seams above are the authoritative coverage
  and the checkpoint agreed for this spec.
- Retaining persist directories when impermanence is toggled off mirrors how the
  Encryption Editor keeps a stored passphrase across an off-toggle; the existing
  "persist declared but impermanence disabled" install-time warning still covers
  the mismatch.
