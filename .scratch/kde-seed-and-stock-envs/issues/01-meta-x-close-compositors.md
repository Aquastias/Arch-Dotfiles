# 01 — Meta+X close on niri & Hyprland

**What to build:** In a full (non-stock) niri or Hyprland session, pressing
`Meta`/`Super`+`X` closes the focused window — matching KDE. The old `Mod+Q`
close bind is removed (the key is freed, not repurposed). (ADR 0113, compositor
half; amends ADR 0096's shared keybind vocabulary.)

**Blocked by:** None — can start immediately.

**Status:** done

- [x] niri `conf.d/keybinds.kdl` binds `Mod+X` to `close-window`; `Mod+Q` no
      longer bound to close.
- [x] Hyprland `conf.d/keybinds.lua` binds `SUPER + X` to `window.close()`;
      `SUPER + Q` no longer bound to close.
- [x] The shared-vocabulary comments in both files reflect Meta+X as the close
      key (compact comment style).
- [x] Compositor-adapter seed-root tests (`NIRI_SEED_ROOT`/`HYPR_SEED_ROOT`)
      assert the seeded keybind file binds `Mod+X` to close and no longer binds
      `Mod+Q` to close.
- [x] Existing test suite stays green.

## Comments

- 2026-09-27 audit: 6dfb331 (kde/niri/hyprland adapter bats,
  environment-resolution/-validation.bats, resolver.bats,
  config/pure-profiles.bats, guided-controller.bats).
