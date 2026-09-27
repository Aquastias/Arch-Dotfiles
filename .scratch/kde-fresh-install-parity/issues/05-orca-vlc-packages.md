# 05 — Orca screen reader + VLC packages

**What to build:** The screen reader works from first login (Orca installed) and
VLC is installed as the video player (its default association is already wired by
ticket 03's `mimeapps.list`). The shipped `haruna` player stays installed as a
fallback. (ADR 0120)

**Blocked by:** None — can start immediately. (The VLC-as-default behaviour is
completed together with ticket 03, but this package addition stands alone.)

**Status:** done

- [x] `orca` is added to the KDE accessibility selection.
- [x] `vlc` is added to the KDE multimedia selection; `haruna` remains selected.
- [x] `packages/resolver.bats` asserts `orca` and `vlc` are in the resolved KDE
      set.

## Comments

- 2026-09-27 audit: 8a32898 (resolver.bats).
