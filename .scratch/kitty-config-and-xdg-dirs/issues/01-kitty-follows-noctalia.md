# 01: Kitty follows Noctalia + single-source color + Nerd font

**What to build:** On a niri/Hyprland session, kitty repaints live when the
Noctalia palette changes, and stays on a fixed default under KDE — the [[Kitty
Theme Template]] behaviour, matching the [[Pi Theme Template]] (ADR 0128/0130).
The terminal's entire palette (background, foreground, 16 ANSI colors, cursor,
selection, borders, tab colors) is driven by the one generated theme file the
committed config includes last; no color knob is left hardcoded. The prompt's
Nerd-Font glyphs render, and the reviewed non-color knobs are applied.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] `"kitty"` removed from the Noctalia `builtin_ids`, so the builtin's
      config-rewriting `apply.sh` never clobbers the stowed `kitty.conf`.
- [ ] A `[theme.templates.user.kitty]` declares a stowed static Mustache input
      (rides the preset's existing `templates/*` seed) mapping the palette's
      `terminal_*`/Material roles into kitty color, output to the generated
      theme file that `kitty.conf` includes.
- [ ] `kitty.conf` includes the generated theme file **last**; the static
      Catppuccin theme files are deleted.
- [ ] Every color knob the generated theme sets is stripped from the split
      config part-files; only non-color knobs remain there.
- [ ] Font family is the installed Nerd variant so p10k glyphs render; automatic
      bold; reviewed size.
- [ ] Reviewed knobs applied: `LS_COLORS` env pass-through part-file dropped
      from the include list; tab bar hidden for a single tab; titlebar follows
      the palette; active-window border follows the accent; transparent
      background and beam cursor kept.
- [ ] The generated theme output is gitignored (seed-only, never stowed).
- [ ] `noctalia-stow.bats` asserts the builtin drop, the user-template
      declaration, and the include wiring.
