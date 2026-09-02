# 04 — Hyprland `hypr-*` compositor plugin slice

**What to build:** the Hyprland plugin slice — Hyprland-native niceties vendored
on a Hyprland install. **As-built note:** the niri slice
(`niri-active-workspace`/`niri-animations`/`niri-displays`) has **no** `hypr-*`
counterpart at the pinned ref (verified via the community-plugins tree), so those
were dropped as verified-absent. Workspace parity is the built-in `workspaces`
bar widget; animations/displays are configured in `hyprland.conf` directly. The
shipped slice (operator's choice) is `hypr-layout-switcher`, `hypr-submap`,
`hypr-screen-mirror` — the latter overlapping the core `wl-screen-mirror` on
Hyprland, kept by explicit choice.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Each candidate `hypr-*` id is confirmed present at the pinned community ref;
      missing ones are dropped and noted.
- [ ] The `hyprland` slice in `install-noctalia.jsonc` lists the confirmed ids
      with their deps; the shared package map exposes them.
- [ ] A Hyprland install vendors the `hyprland` slice (niri still vendors the
      `niri` slice, unchanged).
- [ ] The first-login one-shot enables the vendored slice on Hyprland.
- [ ] The split stays clean: `hypr-*` are vendored/enabled only on Hyprland and
      `niri-*` only on niri; neither slice's ids appear in the shared
      `config.toml`.
- [ ] `hyprland-adapter.bats` asserts the slice is vendored; `resolver.bats`
      reports its deps.
