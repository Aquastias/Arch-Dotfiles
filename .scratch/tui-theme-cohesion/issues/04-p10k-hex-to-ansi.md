# p10k: root/context hexes → ANSI red/yellow

Status: ready-for-agent

## Parent

SPEC: `.scratch/tui-theme-cohesion/SPEC.md` · ADR 0132. Glossary:
[[ANSI-16 Following]], [[Zsh Theme Template]].

## What to build

Remove the last stray hardcoded palette color in the shell prompt. `.p10k.zsh`
hardcodes two Catppuccin Mocha hexes on the root/context segments (red + peach).
Remap them to **ANSI-16 red/yellow** so those warning segments follow the
terminal palette — semantically correct (root/SSH context is a warning) and
consistent with [[ANSI-16 Following]].

This is a fixed-`.p10k.zsh` edit (the committed prompt body), **not** a new key
in the `p10k-accent` [[Zsh Theme Template]] output. Repaint stays relaunch-only,
as the prompt already is.

## Acceptance criteria

- [ ] `.p10k.zsh` contains no hardcoded Catppuccin hex values (root/context
      segments now use ANSI color indices for red/yellow).
- [ ] The root/context warning segments still read as red/yellow, now sourced
      from the terminal's ANSI palette.
- [ ] A test asserts `.p10k.zsh` carries no `#`-hex color on those segments.
- [ ] VM check: on a compositor the root/context segments track a Noctalia
      palette change (on next shell); under KDE they stay Sapphire red/yellow.

## Blocked by

None - can start immediately.
