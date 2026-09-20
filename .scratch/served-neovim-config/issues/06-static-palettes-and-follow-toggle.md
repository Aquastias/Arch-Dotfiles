# 06: Static palette switching + `follow_noctalia` toggle

**What to build:** The theme-selection surface for the static default and the
toggle plumbing. The five Noctalia builtin palettes (rose-pine, catppuccin,
tokyonight, gruvbox, nord) are available as nvim colorschemes and switchable via
a snacks picker that persists the choice. A `follow_noctalia` Lua setting is
read at startup, **default `false`**; while `false`, nvim stays on the chosen
static palette (default Catppuccin Mocha + sapphire accent).

**Blocked by:** 01.

**Status:** done

- [x] The five builtin palettes are installed and load cleanly.
- [x] A snacks colorscheme picker switches the static palette and persists it
      across restarts.
- [x] `follow_noctalia` defaults to `false`; a fresh install is static.
- [x] With `follow_noctalia = false`, the default is Catppuccin Mocha with the
      sapphire accent override.
- [x] The startup read path is structured so the follow branch (ticket 07) can
      hook in without reworking it.
