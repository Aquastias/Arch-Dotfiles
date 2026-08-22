# 04 — First-run suppression seeding

**What to build:** KDE apps stop behaving as if launched for the first
time. Reusing the seed-root seam from ticket 03, the adapter seeds
first-run state into `/etc/skel`: global welcome noise off (Plasma
Welcome Center, tip-of-the-day, what's-new popups) and curated per-app
first-run state for the heavy-hitters (Dolphin, Konsole with a default
profile pre-created, Kate, Okular, Spectacle, Gwenview, Ark). Baloo file
indexing is left enabled so desktop search works. Scope is the curated
set only — not all ~45 apps (ADR Q4-B).

**Blocked by:** 03 — reuses the seed-root variable and skel/xdg write
helper it introduces.

**Status:** ready-for-agent

- [x] The Plasma Welcome Center autostart is hidden in the seeded skel
- [x] Per-app first-run state is seeded **where a dependable Plasma-6
      key exists** — Konsole (a pre-created default profile) and Dolphin
      (a stamped config `Version`). Kate/Okular/Spectacle/Gwenview/Ark
      have no stable first-run flag on Plasma 6, so none is guessed
      (rationale recorded in ADR 0088; invented keys would be noise)
- [x] Baloo indexing is left enabled
- [x] `kde-adapter.bats`: with the seed-root pointed at a temp dir, the
      first-run suppression files land — asserted by presence and key
      value
- [x] Only the curated apps are touched; no attempt at exhaustive
      per-app coverage
