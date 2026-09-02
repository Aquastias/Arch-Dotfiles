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

**Status:** done (behavioral verification pending Seam 2 / ticket 01)

- [x] `config.toml` gains `[idle.behavior.*]` (lock @300s, screen-off @600s) +
      `[lockscreen].lock_before_suspend=true`. Schema matches Noctalia's
      `example.toml` exactly; parses clean. Noctalia respects idle inhibitors,
      so fullscreen/audio hold off idle.
      DEVIATION: the ~2.5 min dim/lock-hint is omitted — Noctalia's top-level
      `[idle]` dim schema wasn't confirmable from example.toml; deferred rather
      than guessed.
- [x] Auto-suspend fires only on a laptop-on-battery.
      DEVIATION: implemented as a RUNTIME battery-status check in a seeded
      helper (`noctalia-idle-suspend`: suspend only if a `BAT*` is
      `Discharging`), not the install-time `laptop` gate — because config.toml
      is byte-identical/portable, runtime gating is the correct home. A desktop
      (no BAT*) or laptop on AC is a no-op. `[idle.behavior.suspend]` @900s
      shells to it via the proven `sh $HOME/.local/bin/...` convention.
- [x] Curated config stays portable — no host-bound state; helper self-gates.
- [x] `wayland_shell=none` seeds none of this (config.toml only under noctalia).
- [x] Adapter bats (niri 21 / hyprland 20) assert config.toml + the idle helper
      seed to /etc/skel; TOML parse + shellcheck green.
- [ ] The desktop-verify idle-active marker (ticket 01) passes — PENDING: needs
      the VM harness (ticket 01) to actually run; idle firing is only provable
      there.

## Comments

Config authored against Noctalia's `example.toml` idle schema (lock/screen-off
verbatim shape) and the existing config.toml `sh $HOME/.local/bin/...` command
convention. Behavioral verification (idle actually locks/blanks/suspends,
inhibitors hold) is a Seam 2 (VM) concern, blocked on ticket 01.
