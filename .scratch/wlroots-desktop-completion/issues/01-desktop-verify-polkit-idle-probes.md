# 01 — Extend desktop-verify prober: polkit-registered + idle-active

**What to build:** In the niri+Noctalia and Hyprland+Noctalia VM cells, the
desktop-verify harness proves — on top of today's wayland-socket + compositor-
process check — that (a) a polkit authentication agent is **registered** on the
session bus and (b) Noctalia's **idle daemon is active**, emitting a per-cell
OK/FAIL marker to the serial console like the existing session probe. Running
this is what **answers the ADR-0100 polkit gate**: does Noctalia's own agent
register out of the box? This is the verification instrument the rest of the
feature is checked against.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The prober emits a distinct OK/FAIL marker for "polkit agent registered"
      in the niri+Noctalia and Hyprland+Noctalia cells.
- [ ] The prober emits a distinct OK/FAIL marker for "Noctalia idle daemon
      active" in those same cells.
- [ ] Markers follow the existing per-session serial-console pattern and do not
      change the KDE cell's behavior.
- [ ] A harness run on a current niri+Noctalia / Hyprland+Noctalia install
      records whether Noctalia's built-in agent registers (the gate answer for
      ticket 03) and whether its idle daemon runs.
- [ ] No change to what installs on a real system — the prober stays a
      test-only VM fixture.
