# 01 — niri shared keybinds + out-of-box media keys

**What to build:** The complete niri side of the shared keybind vocabulary
(ADR 0096). The curated niri config gains the full converged bind set — the
shared binds (terminal, close, launcher, quit, fullscreen, float, focus, move,
workspaces, move-to-workspace, lock, drag move/resize, volume/brightness/media)
plus the niri-only extras (overview, column-width presets, consume/expel,
tabbed columns, center-column, fine width, maximize-to-edges, monitor nav,
directional workspace nav, power-off-monitors, built-in screenshot trio). The
"Important Hotkeys" overlay stays `skip-at-startup` but is now populated. The
Noctalia preset gains `playerctl` so the media keys resolve on a fresh niri box.
Launcher and lock keys spawn Noctalia (`noctalia msg …`).

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The curated niri config carries the full shared + niri-only bind set from
      the ADR 0096 design table, in KDL dialect.
- [ ] `niri validate` passes against the config.
- [ ] The niri-only feature keys land collision-free (overview `Super+O`, width
      presets `Super+R`/`Shift+R`, consume/expel `Super+[`/`]`, tabbed `Super+W`,
      center `Super+C`, fine width `Super+-`/`=`, maximize-to-edges `Super+M`,
      monitor nav `Super+Shift`+HJKL/arrows, directional workspace nav
      `Super+U/I` + `Page_Up/Down`, power-off `Super+Shift+P`).
- [ ] Shared move-to-workspace `Super+Shift`+`<n>` works alongside niri's native
      `Super+Ctrl`+`<n>`; workspace 10 / `Super+0` is not bound.
- [ ] The overlay remains `hotkey-overlay { skip-at-startup }`.
- [ ] `playerctl` is added to the Noctalia preset base in the pure package map
      shared with the Package Resolver.
- [ ] The niri-adapter test asserts `playerctl` is installed with the preset.
- [ ] The full adapter/test suite stays green; the curated config is still
      seeded to `/etc/skel` verbatim (ADR 0095 behavior unchanged).
