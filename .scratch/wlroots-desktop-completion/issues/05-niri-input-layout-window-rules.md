# 05 — niri input / layout / window-rules tuning

**What to build:** A fresh niri+Noctalia login feels tuned, not raw. The curated
`config.kdl` gains an `input` block (touchpad tap-to-click + natural-scroll,
keyboard layout/repeat), a minimal `layout` block, and `window-rules`. Display
scale/mode is deliberately left out — `output` is host-specific and would break
the curated config's portability (ADR 0094/0100). Hyprland already carries its
equivalent input/monitor/look blocks, so this ticket is niri-only.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The curated `config.kdl` gains an `input` block: touchpad tap-to-click and
      natural-scroll, keyboard layout and repeat.
- [ ] The curated `config.kdl` gains a minimal `layout` block + `window-rules`.
- [ ] No `output` block is added (portability rule).
- [ ] Adapter bats assert the updated `config.kdl` seeds to /etc/skel under
      `wayland_shell=noctalia`.
- [ ] Optional: a `niri validate` lint over the seeded config, folded into the
      adapter test only if the niri binary is available in CI.
