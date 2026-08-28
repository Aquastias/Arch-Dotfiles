# 02 — Seed the Rosé Pine palette default

**What to build:** A fresh login comes up themed **Rosé Pine**. The
adapter seeds a `[theme]` table (`source = "builtin"`, `builtin = "Rosé Pine"`)
into skel `.config/noctalia/config.toml`. This is a deliberate exception to
ADR 0090's "seed glue, never look" — only the palette is seeded; the rest
of Noctalia's look is still self-generated on first run. The other four palettes
(Catppuccin, Tokyo-Night, Gruvbox, Nord) are built-in and need no seeding.

**Blocked by:** 01 (shares the `config.toml` seed writer).

**Status:** ready-for-agent

- [ ] `config.toml` in skel carries a `[theme]` table selecting Rosé Pine.
- [ ] No other Noctalia look (bar layout, widgets, wallpaper) is seeded.
- [ ] `niri-adapter.bats` asserts the `[theme]` key is present under
      `niri_shell=noctalia` and absent under `niri_shell=none`.
