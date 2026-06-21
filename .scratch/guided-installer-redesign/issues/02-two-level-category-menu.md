# Two-level Configuration Category menu

Status: ready-for-agent

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

- [ ] Top menu shows the 8 categories with summaries; no per-row section
      prefix repetition.
- [ ] Enter on a category opens its field sub-menu; Esc returns to the
      category list; edits commit on confirm, never on Esc.
- [ ] A category row shows `●` iff any field within it is overridden.
- [ ] sysctl, mirror countries and multilib appear under Options; swap /
      swap size / esp size appear under Disks (still emitting `options.*`).
- [ ] `dotfiles_repo` is gone from the menu and the emitted config.
- [ ] bats for the category model (prior art `tests/config/guided-menu.bats`)
      and a stubbed-fzf loop bats for drill-in navigation.
- [ ] Existing replay path + full bats suite green; an untouched run still
      emits a valid Effective Config.

## Blocked by

None - can start immediately.
