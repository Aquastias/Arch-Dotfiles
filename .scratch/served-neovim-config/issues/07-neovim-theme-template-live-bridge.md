# 07: Neovim Theme Template (live follow bridge)

**What to build:** The [[Neovim Theme Template]] (ADR 0136). A
`[theme.templates.user.nvim]` in `.config/noctalia/config.toml` renders
Noctalia's **16 terminal colors** (accent from `primary`) into a nvim-native
**base16** file. The static template input is stowed; the generated output is
**seed-only and gitignored**, seeded with Catppuccin Mocha Sapphire (ADR 0109),
rewritten only in compositor sessions. When `follow_noctalia = true`, nvim loads
that file and `fs_event`-watches it, re-applying highlights on write mid-session
(no [[Live Theme Bridge]] change). niri/Hyprland follow live; KDE stays fixed.

**Blocked by:** 06.

**Status:** done

- [x] `config.toml` registers `[theme.templates.user.nvim]`; the template input
      is stowed and maps the 16 terminal colors + `primary` accent into base16.
- [x] The generated output is seed-only/gitignored and seeded Mocha Sapphire.
- [x] With `follow_noctalia = true`, rewriting the generated file re-applies the
      theme mid-session (truecolor, full coverage — not 16-color collapse).
- [x] Following is compositor-session-isolated: KDE stays on seeded Mocha
      Sapphire.
- [x] `noctalia-stow.bats` is extended to assert the registration, the stowed
      input, and the seed default — mirroring the kitty/pi/zsh template tests.
