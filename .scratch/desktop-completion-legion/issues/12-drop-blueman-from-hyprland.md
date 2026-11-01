# 12: Drop blueman from Hyprland

**What to build:** Hyprland no longer installs blueman or overwrites its
autostart; Noctalia's Bluetooth panel is the one Bluetooth UI on all three
compositors. Parent: PRD (ADR 0162, amends ADR 0080).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] The Hyprland adapter's blueman section is removed.
- [x] Hyprland adapter bats assert no blueman install or autostart write.
- [x] Hyprland Feature Audit Bluetooth checks (if any) still pass.

## Comments

- 2026-11-02: the blueman autostart never ran under Hyprland (no XDG
  autostart there) but did start in niri/Umbriel on a Hyprland co-install, so
  removal fixes a stray tray too. No Hyprland Bluetooth probe existed.
