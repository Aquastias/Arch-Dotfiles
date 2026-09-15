# Spec: TUI programs cohere via the terminal's 16 ANSI colors

Status: ready-for-agent

Traces to ADR 0132 (TUI programs cohere via the terminal's 16 ANSI colors).
Glossary: [[ANSI-16 Following]], [[Kitty Theme Template]], [[Zsh Theme
Template]], [[User Program]]. Prototype: `.scratch/tui-theme-cohesion-
prototype.html` (throwaway — proves the single-seam repaint).

## Problem Statement

Kitty now ships following Noctalia (ADR 0130), but the rest of the fleet's
shipped color CLIs/TUIs do not cohere with it:

- `eza` renders on its own built-in palette (the `dircolors -b` `LS_COLORS`
  does not cover its permission/size/date/git fields).
- `lazygit` and `yazi` are stock.
- `.p10k.zsh` hardcodes two Catppuccin Mocha hexes on the root/context segments.
- `htop` is stock.

None of these follows a Noctalia palette change on the wl-roots compositors,
and none is guaranteed to sit on the fleet default (Catppuccin Mocha Sapphire,
ADR 0109) under KDE. Only `fzf`, `zsh-syntax-highlighting`, `pi`, `btop` and the
p10k **accent** already follow.

## Solution

Adopt **[[ANSI-16 Following]]** (ADR 0132): point every shipped color CLI/TUI at
the terminal's 16 ANSI colors, which the [[Kitty Theme Template]] already makes
follow the live palette on the compositors and sit on the seeded Sapphire under
KDE. One seam carries all of them — no new Noctalia template, no new ADR-0109
seed point. A per-app hex template stays the fallback for a tool that cannot do
ANSI; none of this set needs it.

## User Stories

1. As a user on a compositor, I want `eza` output to repaint when I change the
   Noctalia palette, so my file listings match the rest of the desktop.
2. As a user under KDE, I want `eza` on the fixed Catppuccin Mocha Sapphire, so
   it matches KDE's app-theming isolation.
3. As a user, I want `eza`'s permission/size/date/git columns themed (not just
   the fields `LS_COLORS` covers), so no column is left on a stock color.
4. As an operator on a fresh box, I want `lazygit` themed on first launch
   without stowing, so a non-stowing user still gets a cohesive git TUI.
5. As an operator, I want the same `lazygit` config hand-stowable from the repo,
   so my machine tracks the repo as the single source.
6. As a user, I want `lazygit`'s borders/selection/diff colors driven by the
   terminal palette, so it follows Noctalia on compositors and Sapphire on KDE.
7. As an operator on a fresh box, I want `yazi` themed on first launch without
   stowing, and hand-stowable from the repo.
8. As a user, I want `yazi`'s panes/mode/selection colors driven by the terminal
   palette, so the file manager coheres on both session classes.
9. As a maintainer, I want `lazygit`/`yazi` seeded configs kept byte-identical
   to the repo stow tree, so the two never silently drift.
10. As a maintainer, I want `lazygit` and `yazi` each owned in exactly one place
    (their program, not also a package list), so the package graph stays
    coherent under Program/package exclusivity.
11. As a user, I want the p10k root/context warning segments to follow the
    palette (ANSI red/yellow) instead of a hardcoded Catppuccin hex, so the last
    stray hardcoded color is gone.
12. As a user, I want `htop` to follow the terminal palette with no new file, so
    it coheres for free and its runtime-rewritten `htoprc` is never clobbered.
13. As a maintainer, I want git/less/ripgrep/fd confirmed already-ANSI, so I
    know they need no change.
14. As a maintainer, I want neovim explicitly out of scope, so its rose-pine
    colorscheme is not disturbed.
15. As a maintainer, I want a documented rule that future terminal tools default
    to ANSI-16 following, so cohesion stays a one-seam habit.

## Implementation Decisions

- **eza — rides `system/zsh`.** Add an ANSI-16 `EZA_COLORS` export to
  `.zsh/env/exports.zsh` (part of the seeded+stowed `system/zsh` program).
  Values are ANSI SGR codes (`30-37`/`90-97`, `1` bold), covering the fields
  `LS_COLORS` misses. No new program.
- **lazygit — new `system/lazygit` [[User Program]].** Mirrors `system/kitty`:
  seeds the config into `$HOME` + `/etc/skel`, byte-identical to the repo stow
  tree, and stays hand-stowable. `gui.theme` in ANSI color **names**
  (`red`…`white`, `default`) + modifiers. **Owns the `lazygit` package**, which
  leaves core `packages.shell` (Program/package exclusivity, ADR 0115).
- **yazi — new `system/yazi` [[User Program]].** Same delivery shape. A
  `theme.toml` in yazi's **named** ANSI colors (names, not numeric indices;
  `reset` = terminal default). **Owns the `yazi` package**, which leaves core
  `packages.shell` (ADR 0115).
- **p10k — remap two hexes.** In `.p10k.zsh` (root/context segments) replace the
  hardcoded Catppuccin Mocha red/peach with ANSI-16 red/yellow. This is a
  fixed-`.p10k.zsh` edit, not a new key in the `p10k-accent` template.
- **htop — no change.** `color_scheme=0` (Default) already renders via the ANSI
  palette; `htoprc` is runtime-rewritten so it must not be stowed.
- **Verify-only.** Confirm `git` diff / `less` / `ripgrep` / `fd` render default
  ANSI; make no change.
- **Static, not generated.** The lazygit/yazi configs are static (nothing
  rewrites them at runtime), so they are **stowed and seeded** — no
  gitignore/seed-only dance, unlike the [[Kitty Theme Template]] output.

## Testing Decisions

Assert external behavior at the delivery and theming seams; prefer existing
seams.

- **Drift seam (new files, existing pattern).** A byte-identical drift test per
  new program keeps its seeded `home/` equal to the repo stow tree — the
  `kitty-program.bats`/`zsh-program.bats` precedent. `lazygit-program.bats` and
  `yazi-program.bats` (siblings), not `configs.bats`.
- **Program-definition seam.** Each `*-program.bats` asserts the program shape
  (config.jsonc `kind: user`; install.sh installs the package and seeds
  `$HOME`/`/etc/skel`) and that the package **left** `packages.shell` (ADR 0115).
- **eza export seam.** Assert the `EZA_COLORS` ANSI-16 export is present in the
  `system/zsh` payload (extend the existing zsh test).
- **p10k seam.** Assert `.p10k.zsh` no longer contains the two Catppuccin hexes
  and the root/context segments use ANSI color indices.
- **End-to-end seam (existing).** On the arch-combined VM: a Noctalia palette
  change repaints `eza`/`fzf` output on the compositor; `lazygit`/`yazi` open
  themed and match the palette; all stay fixed on Sapphire under KDE.

## Out of Scope

- **neovim** — its own rose-pine colorscheme (ADR 0093-era), not ANSI-driven.
- Adding `bat` to the fleet (`BAT_THEME=ansi` stays latent, harmless).
- Any per-app hex Noctalia template or static Catppuccin theme file (the ADR
  0132 fallback, not needed by this set).
- Any change to the [[Kitty Theme Template]], [[Zsh Theme Template]], [[Pi Theme
  Template]], the Sapphire seed (ADR 0109), or KDE isolation (ADR 0104).
- Live (mid-session, no-restart) repaint for `lazygit`/`yazi`/p10k body — bounded
  by each tool's startup-only config read, like the [[Zsh Theme Template]].

## Further Notes

- No new ADR-0109 seed point: these tools carry no palette hex; they defer to
  the terminal, whose seed (kitty `noctalia.conf`) already tracks the default.
- New rule for future terminal-tool additions: default to ANSI-16 following;
  reach for a Noctalia user-template only when the tool cannot express color
  through the terminal's 16 slots.
