# system/yazi program: seeded + stowable, follows ANSI-16

Status: ready-for-agent

## Parent

SPEC: `.scratch/tui-theme-cohesion/SPEC.md` · ADR 0132. Glossary:
[[ANSI-16 Following]], [[User Program]].

## What to build

Ship `yazi` themed and delivered like `system/kitty`/`system/zsh`: a new
`system/yazi` [[User Program]] that seeds a `theme.toml` into `$HOME` +
`/etc/skel` (byte-identical to the repo stow tree) and stays hand-stowable, so a
non-stowing fresh box gets a cohesive file manager.

The `theme.toml` uses yazi's **named** ANSI colors (names, not numeric indices;
`reset` = terminal default), never hex — so yazi's panes, mode line and
selection resolve through the terminal's 16 slots, following Noctalia on the
compositors and Sapphire under KDE. yazi reads theme at launch only, so repaint
is restart-only (the bounded [[Zsh Theme Template]] limit).

The program **owns the `yazi` package**, which must therefore **leave core
`packages.shell`** (Program/package exclusivity, ADR 0115).

## Acceptance criteria

- [ ] A `system/yazi` program exists (`kind: user`), installing the `yazi`
      package and seeding `theme.toml` into `$HOME` and `/etc/skel`.
- [ ] `yazi` is removed from core `packages.shell` (ADR 0115).
- [ ] `theme.toml` colors are yazi named ANSI colors / `reset` only — no hex.
- [ ] The repo stow copy and the seeded `home/` are byte-identical, guarded by a
      new `yazi-program.bats` drift test (kitty/zsh precedent).
- [ ] `yazi-program.bats` also asserts the program shape and the
      `packages.shell` removal.
- [ ] VM check: yazi opens themed on a fresh box; follows a Noctalia palette
      change (on next launch) on a compositor; stays Sapphire under KDE.

## Blocked by

None - can start immediately.
