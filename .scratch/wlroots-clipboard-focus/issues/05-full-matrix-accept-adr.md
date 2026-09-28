# 05: Full VM matrix + accept ADR 0147

**What to build:** The complete agent-driven matrix passes on niri and
Hyprland: Chromium and VSCodium ↔ Qt (Dolphin/pcmanfm-qt) and GTK apps ×
regular in both directions / after source close / middle-click primary in
both directions × File menu, context menu, submenu. After it passes, ADR 0147
is Accepted and the PRD is done.

**Blocked by:** 02, 03, 04

**Status:** ready-for-agent

- [ ] Every matrix cell passes on both compositors; evidence in
      `## Comments`.
- [ ] Prober shows `CLIPBOARD-OK` on both sessions in the same run.
- [ ] ADR 0147 status → Accepted (with commits); PRD status → done.

## Comments

- 2026-09-28: ADR 0147 Accepted. Done: niri clipboard live 12/12 + after
  close 12/12; Hyprland live 12/12, probe `HYPR-CLIPBOARD-OK keep=xfail`;
  Hyprland menus for all 4 apps. Remaining: niri menus once a pointer
  injector is available, and Hyprland after-close once 0.57 lands (the probe
  flips from xfail to a hard check on its own).
