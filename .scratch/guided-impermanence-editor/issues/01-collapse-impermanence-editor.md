Status: done

# Collapse impermanence + persist into one Impermanence Editor

## Parent

`.scratch/guided-impermanence-editor/PRD.md` (ADR 0066)

## What to build

Merge the Guided Installer's two separate impermanence controls on the **Disks**
screen — the inline `impermanence:` on/off toggle field and the standalone
`Add persist directory ▸ …` action row — into one drill-down, the way
Encryption (ADR 0059) and Swap (ADR 0045) already work.

The Disks screen shows a single **`Impermanence ▸ on/off`** row carrying the
standard override `●` dot. Enter opens a new **Impermanence Editor** screen:

- **Off** — collapses to only `enabled: off`.
- **On** — `enabled: on` (Enter toggles), one row per directory already in
  `persist.directories`, a read-only line `curated defaults: N paths always
  persisted` (count only, not enumerated; Enter on it is a no-op), an
  `Add persist directory` action, and a Back action.

Toggling `enabled:` flips `options.impermanence.enabled` with the same
strict-delta normalisation the encryption/swap toggles use (landing back on the
baseline drops the override). The `Add persist directory` action opens the
existing `__persist__` text screen, and committing a directory appends it to
`persist.directories` and returns to the Impermanence Editor (not the Disks
screen). Back / Esc from the editor returns to the Disks category.

Persist-directory **removal is not part of this ticket** — the rows render but
are not yet removable (add-only, exactly today's persist capability, relocated).

Scope: directories only. `persist.files`, `options.impermanence.dataset`, and
`options.impermanence.mount` are not surfaced. No change to the stored config
shape, install-time validation, the hybrid-GPU ban, Export/Save/replay, or the
rollback mechanics — this is a menu-surface change.

## Acceptance criteria

- [ ] The Disks screen renders a single `Impermanence ▸ on`/`off` row (with the
      override dot when overridden) and no longer renders a standalone
      `impermanence:` field row or a Disks-level `Add persist directory` row.
- [ ] Enter on `Impermanence ▸ …` navigates to the `impermanence` editor screen.
- [ ] With impermanence off, the editor renders only `enabled: off`.
- [ ] With impermanence on, the editor renders `enabled: on`, one row per
      persist directory, the `curated defaults: N paths always persisted` line,
      an `Add persist directory` action, and Back.
- [ ] Enter on `enabled:` flips the toggle; toggling back to the baseline value
      leaves no override in Config State (strict delta).
- [ ] The `Add persist directory` action opens the `__persist__` text screen;
      committing a directory appends it to `persist.directories` and returns to
      the Impermanence Editor.
- [ ] Back from the editor returns to the Disks category.
- [ ] The stored keys touched are only `options.impermanence.enabled` and
      `persist.directories[]`; no schema/Export/Save/back-end change.
- [ ] Controller-seam bats cover the render (both states), the toggle strict
      delta, the add round-trip, and navigation — modelled on the existing
      swap/encryption editor tests.

## Blocked by

- None — can start immediately.
