# 03: Click-to-focus on Hyprland; menus stay open

**What to build:** Moving the mouse never steals keyboard focus on either
wlroots session, so File menus, context menus and submenus stay open until an
item is picked. Hyprland moves from focus-follows-mouse to `follow_mouse = 2`
(click-to-focus, hover-scroll kept); niri stays click-to-focus (ADR 0147).
Targeted window rules are added only if ticket 01 shows XWayland popups
still close.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] Hyprland curated input config is click-to-focus; static guard.
- [ ] Static guard: niri curated config has no `focus-follows-mouse`.
- [ ] Popup window rules only if 01's evidence requires them, grounded in
      the Hyprland/Arch wiki.
- [ ] vm-agent run: File menu, context menu, submenu open and an item can be
      selected in Chromium, VSCodium, a Qt app and a GTK app on both
      compositors; evidence in `## Comments`.
