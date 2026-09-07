# 03 — Screenshot: shot

**What to build:** one command that screenshots any session. `shot [file]`
detects the running compositor and auto-selects the tool — `spectacle` under
Plasma (`kwin_wayland`), `grim` under niri/Hyprland — sources the session env,
**wakes the display first** (dpms-on), captures with a timeout, and pulls the PNG
to the host. On a render-stall it reports a clear error instead of hanging. No
new packages: `grim` already ships via the niri set, `spectacle` via KDE.

**Blocked by:** 01 — CLI skeleton (env sourcing, connect).

**Status:** ready-for-agent

- [ ] `shot /tmp/x.png` from a niri/Hyprland session captures via `grim`; from a
      Plasma session captures via `spectacle` — the same command, no flags.
- [ ] The display is woken before capture; a slept/stalled output yields a
      timed-out error message, not a hang.
- [ ] The PNG is pulled back to the host at the given path (or a sensible
      default).
- [ ] `vm-agent.bats` asserts the compositor→tool selection helper
      (`kwin_wayland`→spectacle; niri/Hyprland→grim).
- [ ] Hand-verified on `arch-combined` across a wlroots session and Plasma.
