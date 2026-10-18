# 09: Trim stock KDE

**What to build:** stock KDE is the distro's own Plasma. The stock path
installs `plasma-meta`, the display manager and what they strictly need;
papirus, breeze-gtk and the weather widget move to the curated path only. The
Package Resolver's stock report matches what the stock adapter installs. See
PRD, [[ADR 0112]], [[ADR 0157]].

**Blocked by:** None (can start immediately)

**Status:** done

- [x] `explain-packages kde-pure` lists none of papirus, the weather widget
      (breeze-gtk stays: a hard dependency of plasma-meta)
- [x] Curated KDE (e.g. `desktop`, `arch-kde`) still includes them
- [x] Resolver report and adapter install agree (existing parity test green)
