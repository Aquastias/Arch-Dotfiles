# ADR 0136: Neovim follows Noctalia via its own base16 template, default off

## Status
Accepted. Amends ADR 0132 (ANSI-16 Following), which excluded Neovim from
Noctalia theming ("its own rose-pine colorscheme, not ANSI-driven"). Builds on
the Pi Theme Template pattern (ADR 0128) and the fleet default of Catppuccin
Mocha Sapphire (ADR 0109).

## Context
ADR 0132 pointed shipped TUIs at the terminal's 16 ANSI colors so they cohere
with a live Noctalia palette change with no per-app template — and deliberately
**excluded Neovim**, leaving it on a fixed rose-pine colorscheme. The new
requirement is an editor that (a) ships a curated static default and (b) can
*optionally* follow the live palette, matching a prototype pixel-for-pixel on
the VM.

Neovim runs with `termguicolors` on (truecolor), so it needs palette hexes
**in-process** — it cannot defer to the terminal's 16 slots the way
`eza`/`lazygit` do without collapsing treesitter/LSP highlighting to 16 colors.
Getting the hexes in without a dedicated template (parsing kitty's generated
`noctalia.conf`, or an OSC-4 runtime query) couples the editor to the terminal
or to flaky escape-code round-trips.

## Decision
Neovim follows Noctalia through a **dedicated Neovim Theme Template**, a
`[theme.templates.user.nvim]` that renders Noctalia's **16 terminal colors**
into a nvim-native **base16** file (truecolor, accent from `primary`) — the same
seed-only, gitignored, hot-reloading seam as pi/kitty, terminal-agnostic and
pattern-consistent. Neovim `fs_event`-watches the file and re-applies
mid-session, so the Live Theme Bridge is untouched.

A `follow_noctalia` Lua toggle gates it, **default `false`**: off, Neovim is
static **Catppuccin Mocha with a sapphire accent** (`#74c7ec`), switchable among
the five Noctalia builtin palettes; on, it follows live. Seeded with Catppuccin
Mocha Sapphire and live-rewritten only in compositor sessions, so niri/Hyprland
follow while KDE stays fixed — the same isolation as the other templates.

Neovim is treated as a first-class heavy app (like pi), not an ANSI-16 follower:
the robustness and full-fidelity highlighting are worth one more template.
