# PRD: KDE session theming + first-login fixes (retroactive)

Status: done

Retroactive record — shipped without a grill session. Anchored by
[[ADR 0122]]–[[ADR 0126]]; extends [[ADR 0111]]/[[ADR 0116]]/[[ADR 0121]].

## What shipped

- Strip leaked `QT_QPA_PLATFORMTHEME` on Plasma login (ADR 0122).
- KColorScheme apps follow Noctalia fleet-wide; KDE session self-resets
  (ADR 0123, superseding ADR 0104's combined-box stance).
- qt6ct pointed at the Noctalia KColorScheme so Dolphin accents follow
  (ADR 0124).
- Dolphin seeded without the embedded Terminal panel (ADR 0125).
- Per-activity Kickoff favorites reconstructed at first login (ADR 0126);
  stamp only after the activity manager is up.

## Commits

cb5d857, 5ecf40b, df87942, 2a795d3, 33adf7a, f62f27a.
