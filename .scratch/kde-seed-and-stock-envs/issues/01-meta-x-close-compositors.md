# 01 — Meta+X close on niri & Hyprland

**What to build:** In a full (non-stock) niri or Hyprland session, pressing
`Meta`/`Super`+`X` closes the focused window — matching KDE. The old `Mod+Q`
close bind is removed (the key is freed, not repurposed). (ADR 0113, compositor
half; amends ADR 0096's shared keybind vocabulary.)

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] niri `conf.d/keybinds.kdl` binds `Mod+X` to `close-window`; `Mod+Q` no
      longer bound to close.
- [ ] Hyprland `conf.d/keybinds.lua` binds `SUPER + X` to `window.close()`;
      `SUPER + Q` no longer bound to close.
- [ ] The shared-vocabulary comments in both files reflect Meta+X as the close
      key (compact comment style).
- [ ] Compositor-adapter seed-root tests (`NIRI_SEED_ROOT`/`HYPR_SEED_ROOT`)
      assert the seeded keybind file binds `Mod+X` to close and no longer binds
      `Mod+Q` to close.
- [ ] Existing test suite stays green.
