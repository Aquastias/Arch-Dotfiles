# Glossary + matrix refresh

Status: done (6719e92)

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

- [x] CONTEXT.md Display Manager entry describes the multi-valued rule (SDDM with
      KDE; greetd+tuigreet for Hyprland-only)
- [x] CONTEXT.md Desktop Environment Adapter entry / "KDE only" note corrected
- [x] Install matrix regenerated and includes Hyprland cells
- [x] Matrix tests green

## Blocked by

- Hyprland-only install, end-to-end
- KDE + Hyprland co-install uses SDDM
- Aquamarine DRM pinning on hybrid GPU
- Impermanence uses a real display manager; remove autologin

## Comments

- 2026-09-27 audit: 6719e92.
