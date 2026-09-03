# 01 — GTK apps follow Noctalia (App Theming Bridge: GTK path)

**What to build:** On a fresh install and on a freshly-stowed box, GTK3 and GTK4
applications render in the [[Wayland Shell Companion]]'s live palette (Catppuccin
Mocha Lavender, ADR 0101) and re-render when the Noctalia palette changes —
identically on niri and Hyprland. This is the GTK half of the
[[App Theming Bridge]] (ADR 0102): ship the `adw-gtk3` GTK theme so Noctalia's
`apply.sh` can set `adw-gtk3-dark` and import its generated `noctalia.css`, and
reconcile the stow-owned GTK config so it stops fighting that theme while
preserving the operator's icons, font and cursor.

Scope is GTK3 and GTK4 only (Noctalia's native templates). GTK2 is out of scope.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `adw-gtk3` (repo) is part of the non-negotiable Noctalia base preset, so a
      fresh install has the theme on disk that Noctalia's `apply.sh` needs (it
      sets `adw-gtk3-dark` only if the theme exists).
- [ ] The stow-owned `gtk-3.0` settings set the GTK theme to `adw-gtk3-dark` and
      keep the icon theme (Papirus-Dark), UI font (Noto Sans) and the
      prefer-dark flag.
- [ ] The stow-owned `gtk-4.0` settings carry **no** GTK theme name (so
      libadwaita follows Noctalia's `gtk.css`) while keeping icon theme and font.
- [ ] The stale `breeze_cursors` GTK cursor setting is gone, so GTK apps inherit
      the Bibata cursor (ADR 0098) instead.
- [ ] Noctalia-generated GTK files (`noctalia.css` / `gtk.css`) are left
      Noctalia-owned and are not added to the stow payload.
- [ ] The stale base-preset comment claiming apps are "themed with no extra
      theming" / "Rosé Pine via the Qt template" is corrected to reflect the
      bridge.
- [ ] Seam 1 (`noctalia-stow.bats`) asserts the slimmed gtk-3.0/gtk-4.0 settings
      shape (theme name present in gtk3, absent in gtk4; icon/font kept; no
      `breeze_cursors`) and that the base preset includes `adw-gtk3`.
- [ ] The full installer test suite is green.
