# Glossary + matrix refresh

Status: done (847efdf)

## Parent

`.scratch/hyprland-readd/PRD.md` (ADR 0062, 0050 superseded)

## What to build

The domain glossary and the install matrix reflect that Hyprland is back. The
CONTEXT.md **Display Manager** and **Desktop Environment Adapter** entries (and
the note stating KDE is the only adapter) are corrected: KDE is no longer the
sole desktop, greetd/greetd-tuigreet are back in the vocabulary, and DM selection
is again multi-valued. The Tier-2 install matrix is regenerated so it includes
Hyprland cells derived from the widened desktop enum — no hand-editing.

## Acceptance criteria

- [ ] CONTEXT.md Display Manager entry describes the multi-valued rule (SDDM with
      KDE; greetd+tuigreet for Hyprland-only)
- [ ] CONTEXT.md Desktop Environment Adapter entry / "KDE only" note corrected
- [ ] Install matrix regenerated and includes Hyprland cells
- [ ] Matrix tests green

## Blocked by

- Hyprland-only install, end-to-end
- KDE + Hyprland co-install uses SDDM
- Aquamarine DRM pinning on hybrid GPU
- Impermanence uses a real display manager; remove autologin
