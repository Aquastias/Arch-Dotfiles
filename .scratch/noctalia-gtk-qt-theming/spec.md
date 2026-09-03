# Spec: Noctalia owns GTK/Qt app theming (App Theming Bridge)

Status: ready-for-agent

Anchored by **ADR 0102**. Uses the [[App Theming Bridge]] and
[[Wayland Shell Companion]] glossary terms.

## Problem Statement

I ship a themed desktop — the [[Wayland Shell Companion]] (Noctalia) paints the
shell in Catppuccin Mocha Lavender (ADR 0101) on both niri and Hyprland. But GTK
and Qt applications don't follow it. A Qt file manager and every GTK app render
in default (or mismatched) colors, so the desktop looks inconsistent: the bar,
launcher and notifications are themed, the apps I actually open are not. I want
the apps to follow the theme I set in Noctalia — and to keep following it if I
change the palette later.

## Solution

Make Noctalia's own color templates the single live source of application color.
Noctalia already lists the `gtk3`, `gtk4`, `qt`, and `kcolorscheme` templates in
its `config.toml`; what's missing is the consuming half — the **App Theming
Bridge**. Ship that bridge as part of the non-negotiable Noctalia base preset so
that, on first login on either compositor, GTK and Qt apps render in the current
Noctalia palette with zero manual GUI steps, and re-render automatically when the
palette changes. Scope is exactly what Noctalia natively templates: GTK3, GTK4,
Qt6, and KColorScheme — no GTK2 or Qt5.

## User Stories

1. As an operator, I want GTK apps to render in Noctalia's current palette, so
   that file dialogs, GNOME apps and GTK utilities match my shell.
2. As an operator, I want Qt apps to render in Noctalia's current palette, so
   that pcmanfm-qt and other Qt tools match my shell.
3. As an operator, I want KDE apps (KColorScheme consumers) to match the palette
   without a full Plasma session, so that dolphin/gwenview-style apps look right
   under a bare wlroots compositor.
4. As an operator, I want app theming to work identically on niri and Hyprland,
   so that switching compositor doesn't change how my apps look.
5. As an operator, I want apps to follow a *later* palette change, so that
   cycling or re-selecting a Noctalia palette re-themes apps without me editing
   config files.
6. As an operator, I want app theming to be on by default (part of the base
   preset), so that a fresh install is consistent out of the box.
7. As an operator on a fresh box, I want the correct packages (`adw-gtk3`,
   `qt6ct-kde`) installed automatically, so that Noctalia's apply step actually
   finds the GTK theme and the Qt platform theme it needs.
8. As an operator, I want GTK4/libadwaita apps to follow Noctalia's colors, so
   that modern GTK apps aren't stuck ignoring the theme.
9. As an operator, I do NOT want a GTK4 theme name forced, so that libadwaita
   keeps following Noctalia's `gtk.css` instead of being broken by a competing
   theme.
10. As an operator, I want my icon theme (Papirus-Dark) and UI font (Noto Sans)
    preserved when the GTK theming changes, so that only colors move to Noctalia
    and my icons/fonts don't silently revert to defaults.
11. As an operator, I want GTK apps to use my Bibata cursor (ADR 0098), so that
    the cursor is consistent with the rest of the system rather than the stale
    `breeze_cursors` the old GTK config named.
12. As an operator, I want Qt apps themed on first login with no GUI clicks, so
    that I never have to open qt6ct and hand-pick a scheme.
13. As an operator, I want `QT_QPA_PLATFORMTHEME` set reliably on both
    compositors, so that Qt apps actually consult qt6ct on niri AND under
    Hyprland's `start-hyprland` session.
14. As an operator, I don't want the theming env var placed where Hyprland can't
    see it, so that Qt theming isn't silently broken on one compositor.
15. As an operator, I want the old hand-maintained static Catppuccin Qt color
    files removed, so that there's one source of truth (Noctalia) and no drift.
16. As an operator, I want the old hardcoded `Breeze` GTK theme dropped, so that
    it stops fighting Noctalia's `adw-gtk3-dark`.
17. As an operator stowing this repo standalone (no installer), I want the GTK/Qt
    dotfiles to still carry the bridge, so that `stow .` on any box themes apps
    the same way.
18. As a maintainer, I want the drift guards and shape tests updated for the new
    payload, so that CI catches a regression if a bridge file is dropped or
    malformed.
19. As a maintainer, I want the stale "Rosé Pine via the Qt template" comment on
    the base preset corrected, so that the code's mental model matches reality.
20. As an operator on a bare wlroots box with no gsettings schemas, I want the
    GTK theme still applied via `settings.ini`, so that theming doesn't depend on
    a dconf/gsettings stack Noctalia's `apply.sh` may not find.
21. As an operator, I want the base preset's Qt file manager (pcmanfm-qt) to
    actually be themed, so that the assumption under which it was shipped becomes
    true.

## Implementation Decisions

- **Scope = Noctalia's native templates only.** GTK3, GTK4, Qt6, KColorScheme.
  GTK2 and Qt5 are explicitly excluded (no Noctalia template exists for them).
- **Live-follow, single source.** Noctalia's templates own app color. The 14
  static `.config/qt6ct/colors/catppuccin-mocha-*.conf` files and the hardcoded
  `Breeze` GTK theme name are removed.
- **Packages join the base preset (non-negotiable).**
  - `adw-gtk3` (repo/`extra`) → added to `noctalia_preset_packages` in
    `lib/packages/niri.sh`. Required because Noctalia's `apply.sh` sets
    `adw-gtk3-dark` via gsettings *only if the theme exists on disk*.
  - `qt6ct-kde` (AUR) → the KDE-patched qt6ct exposing the
    `noctalia (KColorScheme)` option; covers plain-Qt6 and KColorScheme in one.
- **`qt6ct-kde` becomes a fleet theming dep, not KDE-only.** It moves from
  resolving under KDE alone to resolving under **kde + niri + hyprland**,
  declared in `aur.theming` of both `install-niri.jsonc` and
  `install-hyprland.jsonc` — mirroring how `bibata-cursor-git` (ADR 0098) is a
  shared cursor declared per-adapter and unioned by the [[Package Resolver]].
  This reverses the qt6ct clause of ADR 0062 (recorded in ADR 0102).
- **GTK `settings.ini` slimmed, not dropped.** Keep the keys Noctalia does not
  set: `gtk-icon-theme-name` (Papirus-Dark), `gtk-font-name` (Noto Sans),
  `gtk-application-prefer-dark-theme`. Set `gtk-theme-name=adw-gtk3-dark` in
  **gtk-3.0 only**. Set **no** `gtk-theme-name` in gtk-4.0 — libadwaita ignores
  theme names and follows `gtk.css`, so a GTK4 theme name would break
  Noctalia-following (this is also why nwg-look's "uncheck GTK4" step is moot: we
  never set one). Drop the stale `gtk-cursor-theme-name=breeze_cursors` line so
  GTK inherits `XCURSOR_THEME=Bibata` (ADR 0098).
- **Noctalia-owned files stay unstowed.** Noctalia writes
  `gtk-{3,4}.0/noctalia.css` and `@import`s it into `gtk.css`; these are
  regenerated at runtime and are never part of the stow payload.
- **Qt pre-seed.** Ship a stow-owned `.config/qt6ct/qt6ct.conf` whose
  `color_scheme_path` points at Noctalia's generated
  `qt6ct/colors/noctalia.conf` with `custom_palette=true`, so Qt is themed on
  first login with no GUI step.
- **Env var per-compositor.** Set `QT_QPA_PLATFORMTHEME=qt6ct` in niri's
  `environment {}` node and Hyprland's `env =` — NOT
  `~/.config/environment.d/`. Hyprland runs via `start-hyprland`, deliberately
  not the systemd-user/uwsm session (ADR 0070), so environment.d would reach niri
  but not Hyprland. Per-compositor mirrors how cursor is already set (ADR 0098).
- **Noctalia template output paths** (from Noctalia source `assets/templates/
  builtin.toml`, for reference during implementation):
  - gtk3 → `$XDG_CONFIG_HOME/gtk-3.0/noctalia.css`
  - gtk4 → `$XDG_CONFIG_HOME/gtk-4.0/noctalia.css`
  - qt → both `$XDG_CONFIG_HOME/qt5ct/colors/noctalia.conf` and
    `$XDG_CONFIG_HOME/qt6ct/colors/noctalia.conf`
  - kcolorscheme → `$XDG_DATA_HOME/color-schemes/noctalia.colors`
- **Comment hygiene.** Correct the stale "Rosé Pine via the Qt template" /
  "inherits Noctalia's Qt template with no extra theming" comments on
  `noctalia_preset_packages` (`lib/packages/niri.sh`) and in the
  [[Wayland Shell Companion]] glossary entry (the latter already done in ADR 0102
  work).

## Testing Decisions

Good tests here assert **external, committed behavior** — the shape of the stow
payload and the resolved package sets — not implementation internals. This repo
has no runtime desktop under test; the two seams are the committed-config shape
and the package resolver, exactly where equivalent decisions (curated look, the
Bibata fleet cursor) are already tested.

- **Seam 1 — `.installer/tests/config/noctalia-stow.bats`** (the curated
  stow-payload shape seam; already reads the committed `.config/*` payloads and
  `lib/packages/niri.sh`). Add assertions that:
  - `gtk-3.0/settings.ini` sets `gtk-theme-name=adw-gtk3-dark`, keeps
    `gtk-icon-theme-name`/`gtk-font-name`/`gtk-application-prefer-dark-theme`,
    and no longer names `breeze_cursors`.
  - `gtk-4.0/settings.ini` carries no `gtk-theme-name` and keeps icon/font.
  - `.config/qt6ct/qt6ct.conf` exists and its `color_scheme_path` targets the
    `noctalia` scheme.
  - No `.config/qt6ct/colors/catppuccin-mocha-*.conf` files remain.
  - `config.kdl` and `hyprland.conf` each set `QT_QPA_PLATFORMTHEME=qt6ct` via
    the compositor's own env mechanism.
  - `noctalia_preset_packages` includes `adw-gtk3`.
  Prior art: this file already asserts config.toml required keys, the
  per-compositor border/cursor plumbing, and the enabled-list drift guard — the
  new assertions follow the same `grep`-the-committed-payload style.
- **Seam 2 — `.installer/tests/profiles/profiles-aur.bats`** (the resolver AUR
  seam). Update so `qt6ct-kde` resolves under **kde, niri and hyprland** (and
  not on a desktop-less host), replacing the current "qt6ct-kde resolves under
  kde / does not resolve under a non-kde DE" cases. Prior art: the adjacent
  `bibata-cursor-git resolves under kde, niri and hyprland` test is the exact
  pattern to mirror.

Both seams are existing and are the highest point in their respective layers
(committed payload shape vs. resolved AUR set); they can't be merged because
those are different resolution layers.

## Out of Scope

- **GTK2 and Qt5 theming.** No Noctalia template exists; deliberately excluded.
- **Kvantum / `QT_STYLE_OVERRIDE`.** The bridge uses qt6ct's platform-theme
  path, not a Kvantum style engine.
- **Wallpaper-derived (Material You) palettes.** The default remains the fixed
  Catppuccin Mocha Lavender community palette (ADR 0101); this spec does not
  change the palette or introduce wallpaper-driven color.
- **Full KDE Plasma.** KColorScheme is served via qt6ct-kde for app-level KDE
  apps; no Plasma session is required or configured here.
- **Runtime/integration testing of a live desktop.** Out of the repo's test
  model; coverage is committed-payload shape + resolver assertions only.
- **Migrating existing installs.** This themes fresh installs and freshly
  stowed configs; no migration tooling for boxes already provisioned.

## Further Notes

- Noctalia's `gtk/apply.sh` uses `adw-gtk3-dark` for dark mode (not `adw-gtk3`),
  only sets the GTK theme if the theme is found on disk, and only touches
  gsettings/dconf when those exist — hence `adw-gtk3` in the preset and the
  slimmed `settings.ini` as the belt on a bare wlroots box.
- The Qt template writes both a qt5ct and a qt6ct scheme file; only the qt6ct one
  is consumed here (Qt5 out of scope), the qt5ct file is harmless.
- Exact Noctalia output paths were read from the Noctalia source
  (`assets/templates/builtin.toml`, `gtk/apply.sh`, `qt/qtct.conf`); the qt6ct
  pre-seed path should be re-confirmed against the installed Noctalia version at
  implementation time.
