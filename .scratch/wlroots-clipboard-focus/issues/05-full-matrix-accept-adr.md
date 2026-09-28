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
