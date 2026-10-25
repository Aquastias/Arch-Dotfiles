# 01: Prefactor: one wlroots compositor set

**What to build:** Every place that asks "is this desktop a wlroots
compositor?" reads one shared set instead of its own niri/Hyprland list:
environment validation/resolution, the Wayland Shell Companion preset, the
Feature Audit Probe Gate shell check, and live-keybinds' session-name
mapping. Behaviour stays the same. After this, adding Umbriel is a one-line
change to the set. Reuse a Commons helper if one fits (Installer Stdlib).

**Blocked by:** None (can start immediately)

**Status:** done

- [x] One owner for the wlroots compositor set; no other niri/Hyprland
      literal list decides wlroots-ness
- [x] Full suite green, golden fixtures unchanged
- [x] No behaviour change on any committed profile

Spec: ../PRD.md · ADR 0159
