# Noctalia owns GTK/Qt app theming

---
Status: accepted. **Supersedes the qt6ct clause of ADR 0062** ("operator brings
qt6ct via dotfiles; qt6ct is theming, not session plumbing") — theming is now a
shipped promise of the shared Wayland Shell Companion, not an operator chore.
---

GTK and Qt apps rendered un-themed under Noctalia: the shell already listed the
`gtk3`/`gtk4`/`qt`/`kcolorscheme` templates in `config.toml`, but nothing wired
the apps to consume the output — so a Qt file manager (`pcmanfm-qt`, already in
the base preset on the false assumption it "inherits Noctalia's Qt template with
no extra theming") and every GTK app fell back to defaults. We make Noctalia's
templates the **single live source** of app color on both compositors: the
palette set in Noctalia (Catppuccin Mocha Lavender, ADR 0101) flows to apps and
tracks any later palette change, replacing the hand-maintained static color
files.

## What this requires

- **Packages (base preset, non-negotiable):** `adw-gtk3` (repo — Noctalia's
  `apply.sh` sets `adw-gtk3-dark` via gsettings *only if the theme exists on
  disk*) and `qt6ct-kde` (AUR — the KDE-patched qt6ct exposing the
  `noctalia (KColorScheme)` option). Covers plain-Qt6 and KDE apps in one.
- **GTK reconciliation:** the stow'd `gtk-3.0`/`gtk-4.0` `settings.ini` are
  *slimmed*, not dropped — they keep the keys Noctalia does **not** set
  (`icon-theme` Papirus-Dark, `font-name` Noto Sans, `prefer-dark`), set
  `gtk-theme-name=adw-gtk3-dark` in **gtk-3.0 only**, and carry **no theme name
  in gtk-4.0** (libadwaita ignores theme names and follows `gtk.css` — so a
  GTK4 theme name would *break* Noctalia-following; this is also why nwg-look's
  "uncheck GTK4" step becomes unnecessary — we never set one). The stale
  `breeze_cursors` line is dropped so GTK inherits `XCURSOR_THEME=Bibata`
  (ADR 0098). Noctalia writes `gtk-{3,4}.0/noctalia.css` and `@import`s it into
  `gtk.css`; those stay Noctalia-owned, never stowed.
- **Qt pre-seed:** a stow'd `qt6ct/qt6ct.conf` points `color_scheme_path` at
  Noctalia's generated `qt6ct/colors/noctalia.conf` with `custom_palette=true`,
  so Qt is themed on first login with zero GUI steps.
- **Env var, per-compositor:** `QT_QPA_PLATFORMTHEME=qt6ct` is set in niri's
  `environment {}` and Hyprland's `env =` — **not** `~/.config/environment.d/`,
  because Hyprland runs via `start-hyprland`, deliberately *not* the
  systemd-user/uwsm session (ADR 0070), so environment.d would reach niri but
  not Hyprland. Per-compositor mirrors how cursor is already set (ADR 0098).

Both package picks trace to the Arch Wiki *Uniform look for Qt and GTK
applications* / *GTK* pages: `adw-gtk3` as the GTK theme that carries the
generated CSS, and a qt6ct platform theme driven by `QT_QPA_PLATFORMTHEME`
(here `qt6ct-kde`, the KDE build that also serves KColorScheme).

## Considered options

- **Static snapshot** (ship fixed Catppuccin color files) — rejected: drifts the
  moment the palette is cycled; defeats "follow the theme I set in Noctalia."
- **`environment.d` for the env var** — rejected on the start-hyprland fact
  above; unreliable on Hyprland.
- **Move GTK icon/font to gsettings seeding** — rejected: a dconf mechanism this
  repo has never used; file-based `settings.ini` stays the pattern and is the
  belt on a bare wlroots box where `apply.sh` finds no gsettings schema.

## Consequences

- **Scope is exactly Noctalia's native templates:** GTK3, GTK4, Qt6, KColor
  Scheme. GTK2 and Qt5 are out (no Noctalia template) — full-toolkit ambition
  yields to "follow what Noctalia generates."
- The 14 static `qt6ct/colors/catppuccin-mocha-*.conf` files and the old
  `Breeze` GTK theme name are removed; Noctalia's `noctalia` scheme is
  authoritative.
- **KDE apps** need the `noctalia` KColorScheme selected once (or the pre-seed
  covers it via qt6ct-kde); no Plasma is required.
