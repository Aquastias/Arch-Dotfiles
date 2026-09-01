# 05 — Hyprland+Noctalia VM `desktop-verify` cell

**What to build:** the install matrix proves a fresh Hyprland+Noctalia box comes
up as a working session, the same way the niri+Noctalia cell does. A
greeter-launched Hyprland session must reach a running compositor with the
Noctalia shell autostarted, taking DRM master via seatd, with the lock reachable
via `ext-session-lock`.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] The matrix generates a Hyprland + `wayland_shell=noctalia` verify cell.
- [ ] `desktop-verify` asserts the session starts, the compositor runs, and the
      Noctalia daemon is up (seatd DRM-master path).
- [ ] The lock path (`ext-session-lock`) is exercised or asserted reachable.
- [ ] The lock-before-suspend known-issue is recorded as a non-blocking note if
      it surfaces on the shipped versions.
