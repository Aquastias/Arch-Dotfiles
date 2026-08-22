# 03 — Theme seeding + seed-root seam (Breeze Dark)

**What to build:** A fresh KDE login is Breeze Dark by default — no
manual theming per install. The KDE adapter seeds the default look into
the system skeleton it can write at chroot time: `/etc/skel/.config/*`
for user-owned, later-editable state and `/etc/xdg/*` for read-only
fallbacks (ADR 0088). Seeded: Breeze Dark global look-and-feel
(`org.kde.breezedark.desktop`), `Papirus-Dark` icons, Breeze cursors.
The adapter's shell phase adds `breeze-gtk` and `kde-gtk-config` so GTK
apps follow the dark look. SDDM is pinned to the Breeze theme in dark so
login-to-session is seamless. This ticket introduces the injectable
**seed-root** variable (default `/`) plus the skel/xdg write helper that
ticket 04 also consumes.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The adapter exposes an injectable seed-root variable defaulting to
      `/`, and a helper that writes skel/xdg files beneath it
- [ ] Seeded `kdeglobals` carries the Breeze Dark color scheme /
      look-and-feel and `Icons=Papirus-Dark`; the Breeze cursor theme is
      set
- [ ] `breeze-gtk` and `kde-gtk-config` install in the shell phase
      (`papirus-icon-theme` already present)
- [ ] SDDM is configured to the Breeze theme in dark
- [ ] `kde-adapter.bats`: with the seed-root pointed at a temp dir, the
      theme files land under `/etc/skel` and `/etc/xdg` with their
      load-bearing keys — asserted by presence and key value, not full
      file bytes
- [ ] No runtime `plasma-apply-lookandfeel` / first-boot service — seed
      is chroot-time file placement only (ADR 0088)
