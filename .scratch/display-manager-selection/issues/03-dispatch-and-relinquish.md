# 03 — Dispatch the DM adapter; DE adapters relinquish the display manager

**What to build:** The atomic contract flip that makes the feature real. The
Environment Runner, after iterating the resolved desktop array and invoking each
Desktop Environment Adapter, invokes the single Display Manager Adapter matching
the resolved `display_manager` by directory convention, skipping when the
resolved value is `none`. Simultaneously the Desktop Environment Adapters give
up the display manager: the KDE adapter no longer installs or enables SDDM, and
the Hyprland adapter no longer installs greetd/tuigreet nor writes the greeter
config (it keeps writing the curated session files and enabling seatd). After
this ticket a hand-authored profile with `display_manager: sddm` on a Hyprland
or KDE + Hyprland machine actually greets with SDDM, and greetd is reachable on
a KDE-only machine.

**Blocked by:** 01, 02.

**Status:** ready-for-agent

- [ ] The Environment Runner invokes `extras/dm/<dm>/<dm>.sh` for the resolved
      `display_manager`, after the desktop loop, with no greeter name hardcoded;
      dispatch is skipped when the resolved value is `none`.
- [ ] The KDE adapter no longer installs or enables SDDM (`sddm-kcm` stays a KDE
      application).
- [ ] The Hyprland adapter no longer installs greetd/tuigreet nor writes the
      greeter config; it still writes the curated session files and enables
      seatd.
- [ ] The VM environment matrix stays green: a KDE + Hyprland co-install greets
      with greetd, a KDE-only install greets with SDDM (unchanged defaults via
      `auto`), and both desktops remain selectable at the greeter.
- [ ] The environment-runner bats assert the DM adapter is dispatched after the
      desktops and skipped on `none`; the updated KDE and Hyprland adapter bats
      assert neither touches a display manager.
