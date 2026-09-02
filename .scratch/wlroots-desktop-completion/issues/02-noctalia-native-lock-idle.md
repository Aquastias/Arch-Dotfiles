# 02 — Enable Noctalia-native lock + idle in config.toml

**What to build:** On both niri and Hyprland, the Noctalia shell locks and
manages idle automatically, configured entirely in the stow-owned / skel-seeded
`config.toml` — zero new packages, byte-identical across compositors (ADR
0097/0100). On inactivity the screen dims (~2.5 min), locks (~5 min), then
blanks via DPMS (~10 min); the session locks before it suspends; a laptop on
battery eventually suspends while a desktop never auto-suspends; idle is
inhibited while fullscreen video or audio plays. The manual lock keybind keeps
working unchanged.

**Blocked by:** 01 (uses the idle-active probe to verify idle actually fires in
the VM).

**Status:** ready-for-agent

- [ ] `config.toml` enables Noctalia's built-in locker and idle daemon with the
      policy above (dim → lock → DPMS-off, lock_before_suspend on, inhibit on
      fullscreen/audio).
- [ ] Auto-suspend fires only on a laptop-on-battery, gated by the existing
      `laptop` detection; desktops get lock + DPMS but no suspend leg.
- [ ] The curated config stays portable — no host-bound / output-keyed state is
      introduced (ADR 0094 rule).
- [ ] `wayland_shell=none` seeds none of this (bare-compositor symmetry).
- [ ] Adapter bats assert the updated `config.toml` seeds to /etc/skel under
      `wayland_shell=noctalia`.
- [ ] The desktop-verify idle-active marker (ticket 01) passes in both wlroots
      cells.
