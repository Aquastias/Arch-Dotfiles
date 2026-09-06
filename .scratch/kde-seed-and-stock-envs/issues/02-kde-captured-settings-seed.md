# 02 — KDE captured-settings seed

**What to build:** A fresh KDE login lands on the setup captured from
`arch-combined` — custom dark colours, four virtual desktops, kwin plugins +
tiling, faster animations, 30-min lock, klipper history, the panel widget
layout, Dolphin/Konsole/KFileDialog preferences, empty-session login — instead
of Plasma first-run. The KDE [[Desktop Environment Adapter]] vendors the captured
config files and seeds them verbatim into `/etc/skel`, konsave-style. This also
delivers KDE's Meta+X close, which rides in the captured `kglobalshortcutsrc`.
(ADR 0111; ADR 0113 KDE half.)

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] These `~/.config/` files are vendored into the KDE adapter and copied
      verbatim into `/etc/skel/.config/`: `kdeglobals`, `kwinrc`, `plasmarc`,
      `plasmashellrc`, `plasma-org.kde.plasma.desktop-appletsrc`,
      `kglobalshortcutsrc`, `kcminputrc`, `klipperrc`, `kscreenlockerrc`,
      `ksmserverrc`, `dolphinrc`, `konsolerc`, `plasma-localerc`.
- [ ] The custom colour scheme rides inline in `kdeglobals` (no separate
      `.colors` file needed).
- [ ] The captured files replace the ADR 0088 Breeze-Dark heredocs for the look
      files; ADR 0088's non-look seeds are retained (Plasma Welcome hidden,
      Baloo on, SDDM theme drop-in, GTK cursor inherit).
- [ ] `kscreenrc` and `kwinoutputconfig.json` are NOT seeded (host-specific
      monitor state, ADR 0110); akonadi/PIM state and caches are NOT seeded.
- [ ] The seeded `kglobalshortcutsrc` binds Window Close to
      `Alt+F4\tMeta+X` (KDE keeps both).
- [ ] `tests/extras/kde-adapter.bats` (driving `kde.sh` with `KDE_SEED_ROOT`)
      asserts the full file list lands in skel, `kdeglobals` carries the custom
      colours, and `kglobalshortcutsrc` binds Meta+X.
- [ ] The combined-host isolation is unchanged: the App Theming Bridge's
      `kcolorscheme` template stays off so Noctalia never merges into
      `kdeglobals` (ADR 0104).
