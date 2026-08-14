# 02 — Pacman category in the Guided menu

**What to build:** an operator opening the Guided Installer sees a new **Pacman**
Configuration Category positioned immediately after Mirrors & Repositories, with
the six pacman `[options]` settings listed as rows in the same style as every
other section — five bool toggles plus a numeric `ParallelDownloads` field.
Editing a row persists into `options.pacman.*`, the `●` override marker appears
on changed rows, and the same fields are settable through the replay editors so
non-interactive guided runs configure them too. See ADR 0074.

**Blocked by:** 01 — options.pacman.* config-state foundation.

**Status:** ready-for-agent

- [ ] A **Pacman** category appears in the top-level menu directly after
      "Mirrors & Repositories".
- [ ] The category lists six rows with the agreed labels/defaults: ILoveCandy,
      Color, VerbosePkgLists, DisableDownloadTimeout, NoProgressBar (toggles) and
      ParallelDownloads (numeric/text, default 5).
- [ ] Each bool row uses the toggle editor; `ParallelDownloads` uses the
      free-text/numeric editor (same kind as `esp size`).
- [ ] Editing a row writes to `options.pacman.*` in the Config State; the value
      survives save/replay (validates under ticket 01's schema).
- [ ] An overridden row shows `●`; an untouched row shows its default with no `●`.
- [ ] Replay editors set each of the six fields non-interactively.
- [ ] Seam 1 bats assert the category placement, the six rows (labels, kinds,
      defaults), and the override-flag behaviour. Prior art:
      `tests/config/guided-menu.bats`, `tests/config/menu-enum.bats`.
