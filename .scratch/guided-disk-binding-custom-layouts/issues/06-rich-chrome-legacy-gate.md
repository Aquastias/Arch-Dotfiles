# 06 — Rich chrome + legacy gate

Status: done
Type: AFK

## Parent

`.scratch/guided-disk-binding-custom-layouts/PRD.md`

## What to build

Separate actions from data and add a persistent status footer, so the menu lists
hold only real choices and every screen shows where you are and what you can do —
while still working on the older fzf a lagging install ISO may ship.

- **Actions → keys.** `← Back`/`＋ Add`/`✗ remove`/create leave the lists onto
  keybindings: `^A` = add/new/create, `^X` = remove/delete, Esc = back;
  `^Z`/`^Y`/`^R` stay undo/redo/reset. Lists then contain only data.
- **Chrome zones (rich).** Header = global nav keys; footer (`change-footer`) =
  this screen's context actions + a one-line live summary (e.g. `tank0 · mirror ·
  2 bound`); breadcrumb on `--list-label` (`Guided ▸ Disks ▸ tank0`); the static
  ` Guided Installer ` title stays on the outer border-label; rounded list/footer
  borders.
- **Version gate.** Detect `fzf --version` once at launch into a cached boolean.
  **Rich chrome iff fzf ≥ 0.62.** Below that (0.36–0.61 band), fall back to
  today's action-rows-in-list + header/border, no footer/breadcrumb. No hard-
  floor bump and no `pacman -Sy fzf` at menu start (protects offline authoring).
- **Feature parity.** In-Menu Disk Binding, custom layouts, and per-pool editing
  behave identically in both chrome modes — only presentation differs.

## Acceptance criteria

- [ ] In rich mode, editor/list screens render only data rows; add/remove/create
      are on `^A`/`^X` and emit the right dispatch actions (fzf-entry seam).
- [ ] The `render` action string carries per-screen `change-footer` (context +
      summary), `change-list-label` (breadcrumb), and `change-header` (nav keys)
      content (fzf-entry seam).
- [ ] The version gate returns rich for a stubbed `fzf ≥ 0.62` and legacy below,
      as a pure function (pure seam).
- [ ] In legacy mode, action rows reappear in the lists and no footer/breadcrumb
      actions are emitted; all features remain reachable.
- [ ] Full existing bats suite stays green.

## Blocked by

- 05 — Freeform custom layouts.
