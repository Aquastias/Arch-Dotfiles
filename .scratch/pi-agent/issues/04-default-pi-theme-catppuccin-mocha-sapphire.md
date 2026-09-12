# 04: Default pi theme = Catppuccin Mocha Sapphire

**What to build:** Pi's TUI defaults to Catppuccin Mocha Sapphire so it matches
the rest of the desktop, on any box including offline and KDE.

Scope: ship a seeded `~/.pi/agent/themes/noctalia.json` carrying the full 53-token
map with accent `#74c7ec`, and set `theme: "noctalia"` in `settings.json`. The
single `noctalia.json` is the file later live-rewritten by ticket 05; on its own
it is a static Catppuccin Mocha Sapphire theme (so KDE and offline boxes are
themed). Token map is from the approved prototype: `accent/borderAccent/toolTitle/
mdLink/syntaxKeyword = primary #74c7ec`, `text = on_surface #cdd6f4`,
`dim/outline = #6c7086`, `background = surface #1e1e2e`, `success = green`,
`error = red #f38ba8`, `warning = yellow`, `thinkingHigh border = red`,
`toolDiffAdded = green`, `toolDiffRemoved = red`, `bashMode = peach`, terminal
tokens from the palette's `terminal_*` roles. Anchored by ADR 0128 / ADR 0109.

**Blocked by:** 01 (needs the installed pi + seed/stow config tree + settings.json).

**Status:** ready-for-agent

- [ ] `noctalia.json` (53 tokens, accent `#74c7ec`) is seeded into `/etc/skel`
      and present in the stow tree.
- [ ] `settings.json` sets `theme: "noctalia"`.
- [ ] `pi-agent.bats` asserts the seeded accent `#74c7ec` and the `theme` key.
- [ ] On the `arch-combined` VM, the pi TUI renders Catppuccin Mocha Sapphire,
      including under a KDE session.
