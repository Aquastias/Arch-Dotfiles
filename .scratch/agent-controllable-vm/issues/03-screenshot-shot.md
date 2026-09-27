# 03 — Screenshot: shot

**What to build:** one command that screenshots any session. `shot [file]`
detects the running compositor and auto-selects the tool — `spectacle` under
Plasma (`kwin_wayland`), `grim` under niri/Hyprland — sources the session env,
**wakes the display first** (dpms-on), captures with a timeout, and pulls the PNG
to the host. On a render-stall it reports a clear error instead of hanging. No
new packages: `grim` already ships via the niri set, `spectacle` via KDE.

**Blocked by:** 01 — CLI skeleton (env sourcing, connect).

**Status:** done

- [x] `shot /tmp/x.png` from a niri/Hyprland session captures via `grim`; from a
      Plasma session captures via `spectacle` — the same command, no flags.
- [x] The display is woken before capture; a slept/stalled output yields a
      timed-out error message, not a hang.
- [x] The PNG is pulled back to the host at the given path (or a sensible
      default).
- [x] `vm-agent.bats` asserts the compositor→tool selection helper
      (`kwin_wayland`→spectacle; niri/Hyprland→grim).
- [ ] Hand-verified on `arch-combined` across a wlroots session and Plasma.

## Comments

- 2026-09-27 audit: 24258ce (shot), 40ff70b (XDG_SESSION_TYPE into launched
  apps). Hand-verification not recorded — left unticked.
