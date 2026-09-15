# eza follows the terminal's 16 ANSI colors

Status: ready-for-agent

## Parent

SPEC: `.scratch/tui-theme-cohesion/SPEC.md` · ADR 0132 (TUI programs cohere via
the terminal's 16 ANSI colors). Glossary: [[ANSI-16 Following]].

## What to build

Make `eza` render through the terminal's 16 ANSI colors so it follows a live
Noctalia palette change on the wl-roots compositors and sits on the seeded
Catppuccin Mocha Sapphire under KDE — the same seam kitty already themes. eza
currently uses its own built-in palette because the `dircolors -b` `LS_COLORS`
does not cover its permission/size/date/git columns.

Add an ANSI-16 `EZA_COLORS` export to the `system/zsh` program's shell env
(`.zsh/env/exports.zsh`), which is already seeded **and** stowed — so this needs
no new program. Values are ANSI SGR codes (`30-37`/`90-97`, `1` bold), never
hex, so they resolve through whatever the terminal's 16 slots currently are.
Cover the fields `LS_COLORS` misses (permissions, size, date, user/group, git).

## Acceptance criteria

- [ ] `EZA_COLORS` is exported from the `system/zsh` payload, in ANSI SGR codes
      (no `38;5;` / `38;2;` hex).
- [ ] eza's permission, size, date and git columns are themed by the export (not
      left on eza defaults).
- [ ] The export is delivered by both the seed (`/etc/skel` / `$HOME`) and the
      stow tree, byte-identical (rides the existing `system/zsh` delivery).
- [ ] The existing zsh program test asserts the `EZA_COLORS` ANSI-16 export is
      present.
- [ ] VM check: a Noctalia palette change on a compositor repaints `eza` output
      on the next run; under KDE `eza` stays on Catppuccin Mocha Sapphire.

## Blocked by

None - can start immediately.
