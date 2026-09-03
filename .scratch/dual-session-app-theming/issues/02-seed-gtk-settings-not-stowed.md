# 02 — Seed GTK `settings.ini` as real files instead of stowing them

**What to build:** The operator's dotfiles repo must not go dirty after a KDE
login. Plasma's `kde-gtk-config` rewrites the GTK `settings.ini` at every login;
because those files ship as stow symlinks into the repo, the write lands in the
repo. Move them out of the stow payload and have the shared Noctalia preset (the
compositor-agnostic module sourced by both the niri and Hyprland
[[Desktop Environment Adapter]]s) seed real files into `/etc/skel`. On KDE that
seeded file is Plasma's to manage at runtime; on a compositor it provides
`adw-gtk3-dark` as the GTK3 base while Noctalia's live `gtk.css` supplies colors.
A KDE-only host seeds nothing — Plasma generates the file on first login.
Anchored by ADR 0104 (amends ADR 0102).

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `gtk-3.0/settings.ini` and `gtk-4.0/settings.ini` are removed from the
      stow payload so neither is symlinked into the repo.
- [ ] The shared Noctalia preset seeds both into `/etc/skel`: gtk-3.0 carries
      `adw-gtk3-dark` + `Papirus-Dark` icons + `Noto Sans` font +
      `prefer-dark`; gtk-4.0 carries no theme name (libadwaita follows
      `gtk.css`).
- [ ] The seeds are host-neutral — no `gtk-xft-dpi`/scaling — and carry no stale
      `breeze_cursors`.
- [ ] The seed is written only when a compositor with `wayland_shell=noctalia`
      runs; a KDE-only host gets no seeded GTK `settings.ini`.
- [ ] The `noctalia-stow.bats` drift guard reads the preset's seed (not a repo
      file): asserts the repo files are absent, the seeded gtk-3.0/gtk-4.0
      content is correct, and no host DPI or breeze cursor leaks in.
- [ ] `qt6ct.conf` remains stowed and unchanged; the niri/Hyprland adapter
      suites and the configs-conflict-detector stay green.
