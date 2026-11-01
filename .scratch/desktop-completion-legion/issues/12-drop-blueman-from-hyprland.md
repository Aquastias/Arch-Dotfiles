# 12: Drop blueman from Hyprland

**What to build:** Hyprland no longer installs blueman or overwrites its
autostart; Noctalia's Bluetooth panel is the one Bluetooth UI on all three
compositors. Parent: PRD (ADR 0162, amends ADR 0080).

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The Hyprland adapter's blueman section is removed.
- [ ] Hyprland adapter bats assert no blueman install or autostart write.
- [ ] Hyprland Feature Audit Bluetooth checks (if any) still pass.
