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

- [ ] Global welcome/tips/what's-new are disabled in the seeded skel
- [ ] Per-app first-run state is seeded for Dolphin, Konsole, Kate,
      Okular, Spectacle, Gwenview, Ark (a default Konsole profile
      exists)
- [ ] Baloo indexing is left enabled
- [ ] `kde-adapter.bats`: with the seed-root pointed at a temp dir, the
      first-run suppression files land — asserted by presence and key
      value
- [ ] Only the curated apps are touched; no attempt at exhaustive
      per-app coverage
