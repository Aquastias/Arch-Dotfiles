# KDE + Hyprland co-install uses SDDM

Status: ready-for-agent

## Parent

`.scratch/hyprland-readd/PRD.md` (ADR 0062, 0005)

## What to build

When both KDE and Hyprland are in the resolved desktop set, SDDM is the display
manager and its greeter offers both a Plasma session and a Hyprland session, the
Hyprland one launching directly via the session override. The Hyprland adapter
skips installing/enabling greetd whenever KDE is present in the full resolved
desktop set, so the decision is independent of adapter execution order. The KDE
adapter is unchanged and continues to always enable SDDM.

## Acceptance criteria

- [ ] Hyprland adapter skips greetd when KDE is in the resolved desktop set
- [ ] Behavior is identical for desktop order KDE+Hyprland and Hyprland+KDE
- [ ] SDDM greeter offers both sessions; the Hyprland session uses the direct-
      launch override
- [ ] KDE adapter still enables SDDM (unchanged)
- [ ] `hyprland-adapter.bats` covers the greetd-skipped-when-KDE-present case;
      environment-runner dispatch of both adapters is green

## Blocked by

- Hyprland-only install, end-to-end
