# system/lazygit program: seeded + stowable, follows ANSI-16

Status: ready-for-agent

## Parent

SPEC: `.scratch/tui-theme-cohesion/SPEC.md` · ADR 0132. Glossary:
[[ANSI-16 Following]], [[User Program]].

## What to build

Ship `lazygit` themed and delivered like `system/kitty`/`system/zsh`: a new
`system/lazygit` [[User Program]] that seeds a lazygit config into `$HOME` +
`/etc/skel` (byte-identical to the repo stow tree) and stays hand-stowable, so a
non-stowing fresh box still gets a cohesive git TUI.

The config's `gui.theme` uses ANSI color **names** (`red`, `green`, …, `white`,
and `default` for terminal fg/bg), never hex — so lazygit's borders, selection
and diff colors resolve through the terminal's 16 slots, following Noctalia on
the compositors and Sapphire under KDE. lazygit reads config at startup only, so
repaint is restart-only (the bounded [[Zsh Theme Template]] limit).

The program **owns the `lazygit` package**, which must therefore **leave core
`packages.shell`** (Program/package exclusivity, ADR 0115) — the same move
`kitty` made.

## Acceptance criteria

- [ ] A `system/lazygit` program exists (`kind: user`), installing the `lazygit`
      package and seeding the config into `$HOME` and `/etc/skel`.
- [ ] `lazygit` is removed from core `packages.shell` (ADR 0115).
- [ ] `gui.theme` colors are ANSI names / `default` only — no hex values.
- [ ] The repo stow copy and the seeded `home/` are byte-identical, guarded by a
      new `lazygit-program.bats` drift test (kitty/zsh precedent, not
      `configs.bats`).
- [ ] `lazygit-program.bats` also asserts the program shape and the
      `packages.shell` removal.
- [ ] VM check: lazygit opens themed on a fresh box; follows a Noctalia palette
      change (on next launch) on a compositor; stays Sapphire under KDE.

## Blocked by

None - can start immediately.
