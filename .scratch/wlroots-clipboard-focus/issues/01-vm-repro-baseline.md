# 01: VM repro baseline: clipboard + menu focus on both compositors

**What to build:** Reproduce both bugs on niri and Hyprland (the
[[Wayland Shell Companion]] sessions) in the agent-controllable VM, before any
fix lands. Chromium is installed in the test VM only. For each app in the
matrix, record whether its window runs as native Wayland or XWayland, and
record whether Noctalia #3793 ("history has it, `wl-paste` says empty")
shows up. The findings decide what tickets 02–04 do (ADR 0147).

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] Chromium present in the wlroots test VM, no host profile changed.
- [ ] Per compositor: Chromium, VSCodium ↔ Dolphin/pcmanfm-qt (Qt) and a GTK
      app, regular copy/paste in both directions attempted; pass/fail
      recorded.
- [ ] Paste after closing the source app, and middle-click primary in both
      directions, attempted; pass/fail recorded.
- [ ] File menu, context menu and submenu attempted in each app on each
      compositor; pass/fail recorded.
- [ ] Wayland vs XWayland recorded per app per compositor.
- [ ] Noctalia #3793 seen or not seen, on the shipped Noctalia version.
- [ ] Findings + screenshot evidence in `## Comments`, stating whether
      ticket 04 is needed.
