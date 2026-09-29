# 15: Desktop/theming probes

**What to build:** probes for the desktop layer: Noctalia-generated
theme files present/consistent, Qt via Dolphin and GTK via a GTK app (ADR
0117 convention) launch clean with screenshots, xdg user dirs on wlroots,
KDE settings/favorites, wlroots clipboard keep-alive.

**Blocked by:** 08, 09

**Status:** ready-for-agent

- [ ] Each checkable theming state a probe check
- [ ] App launches screenshotted into visual review
- [ ] Runs in every compositor session of the variant
