# 05 — Palette-switch control-center tiles

**What to build:** From the control center, one click switches between the five
built-in palettes (Rosé Pine, Catppuccin, Tokyo-Night, Gruvbox, Nord). The
adapter seeds a `custom-shortcut` tile per palette, each calling
`qs -c noctalia-shell ipc call colorScheme set <Name>`. Palette switching uses
built-in theming — no `config-swap`.

**Blocked by:** 02, 03 (needs the seeded palette default and the
`custom-shortcut` plugin installed).

**Status:** ready-for-agent

- [ ] One `custom-shortcut` tile per built-in palette is seeded.
- [ ] Each tile invokes `colorScheme set` with the correct palette name.
- [ ] No `config-swap` plugin is involved.
- [ ] `niri-adapter.bats` asserts the five tiles and their target palette names.
