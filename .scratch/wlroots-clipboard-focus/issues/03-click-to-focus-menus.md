# 03: Click-to-focus on Hyprland; menus stay open

**What to build:** Moving the mouse never steals keyboard focus on either
wlroots session, so File menus, context menus and submenus stay open until an
item is picked. Hyprland moves from focus-follows-mouse to `follow_mouse = 2`
(click-to-focus, hover-scroll kept); niri stays click-to-focus (ADR 0147).
Targeted window rules are added only if ticket 01 shows XWayland popups
still close.

**Blocked by:** 01

**Status:** done

- [x] Hyprland curated input config is click-to-focus; static guard.
- [x] Static guard: niri curated config has no `focus-follows-mouse`.
- [x] Popup window rules only if 01's evidence requires them, grounded in
      the Hyprland/Arch wiki.
- [x] vm-agent run: File menu, context menu, submenu open and an item can be
      selected in Chromium, VSCodium, a Qt app and a GTK app on both
      compositors; evidence in `## Comments`. (both: ticket 03 + 05 comments.)

## Comments

- 2026-09-28: Hyprland `input.lua`: `follow_mouse = 2`,
  `float_switch_override_focus = 0`, `misc.anr_missed_pings = 15` (Hyprland
  wiki config-options: defaults 1 / 1 / 5). Stow guard, plus a guard that
  niri has no `focus-follows-mouse`. VM (Hyprland, applied live via `hyprctl
  eval`, ydotool pointer, kitty as the window crossed):
  - kwrite: File → File Actions submenu stays open across kitty; File → New
    runs (title Welcome → Untitled).
  - VSCodium: ≡ → File submenu stays open across kitty; New Text File runs
    (Untitled-1).
  - Chromium: right-click context menu stays open across kitty; Save as…
    opens the portal dialog.
  - GTK (zenity, floating): the context menu lost focus to kitty until
    `float_switch_override_focus = 0`; after that, Paste lands the token.
  - Before the change (`follow_mouse = 1`): VSCodium's menu closed when the
    pointer crossed kwrite (repro).
  - niri not pointer-driven (ydotool ignored, wlrctl build declined). niri
    is click-to-focus by default, so hover can't move focus.
