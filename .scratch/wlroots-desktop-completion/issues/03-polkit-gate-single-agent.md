# 03 — Resolve polkit gate + wire the single agent

**What to build:** A GUI app that needs root (mount a disk, open a firewall
tool) shows a password prompt on both niri and Hyprland, served by **exactly
one** polkit agent per session (never two racing). The choice is made once at
implementation time from ticket 01's result, not per install (ADR 0100):

- **If Noctalia's own agent registers** → remove the unconditional
  `polkit-kde-agent` install from both wlroots [[Desktop Environment Adapter]]s;
  add no agent package; the KDE adapter keeps its own `polkit-kde-agent`.
- **If it does not** → ship the KDE-aware fallback ladder keyed on the resolved
  `environment.desktop` set: KDE co-installed → the wlroots sessions reuse the
  already-present `polkit-kde-agent`; no KDE → install `hyprpolkitagent`
  (official `extra` repo) and autostart it. Any needed autostart lives in the
  shared preset module so niri and Hyprland stay aligned.

**Blocked by:** 01 (needs the polkit-registered probe result to pick a branch).

**Status:** ready-for-agent

- [ ] The polkit gate is resolved from ticket 01 and the winning branch is
      implemented; the outcome is recorded (ADR 0100 reference).
- [ ] Exactly one polkit agent is active per wlroots session — never two.
- [ ] Verify-pass path: `polkit-kde-agent` no longer installed by either
      wlroots adapter; the `niri-adapter.bats` assertion that it *is* installed
      is flipped; the KDE adapter test stays green.
- [ ] Verify-fail path: the KDE-else-hyprpolkitagent ladder installs/autostarts
      the correct agent for each co-installed `environment.desktop` set.
- [ ] The [[Package Resolver]] reports the resulting agent set with no drift
      from what installs.
- [ ] The desktop-verify polkit-registered marker (ticket 01) passes in both
      wlroots cells.
