# 04: `auto` resolves to noctalia-greeter on KDE-free Noctalia hosts

**What to build:** With `display_manager: auto`, a KDE-free non-empty desktop
set (niri, Hyprland, or both) with `wayland_shell: noctalia` gets
noctalia-greeter; `wayland_shell: none` or `stock` falls back to greetd +
tuigreet; any set containing `kde` keeps SDDM; an empty set stays `none`.
The installer and the Package Resolver resolve in lockstep, and Guided
previews the resolved `auto` correctly ([ADR 0158], amending [ADR 0091]).

**Blocked by:** 03.

**Status:** ready-for-agent

- [x] Installer resolution and resolver resolution agree for every
      desktop-set × shell × stock combination (tested).
- [x] Guided shows the right resolved DM for `auto` — n/a: Guided shows the
      raw `auto`, it never previews the resolved DM.
- [ ] VM run of a default niri profile boots to noctalia-greeter.
- [ ] ADR 0158 status → implemented.
