# Qt/GTK/KDE app theming under bare wlroots + Noctalia (offline-safe)

Research date: 2026-09-05. Primary sources only (upstream source/docs, Arch
Wiki, first-party APIs). Local package: `qt6ct-kde 0.11-8` installed;
`noctalia-shell` NOT installed on this box (findings from upstream source).

## Executive summary
1. Noctalia is now a compiled C++ app; builtin palettes (Catppuccin, Rosé Pine,
   …) are baked into the binary and render ALL templates offline. With
   `source="community"` an offline first boot silently FALLS BACK to the builtin
   named by `[theme].builtin` — apps are themed offline (builtin Catppuccin),
   NOT unthemed. The daemon writes `qt6ct/colors/noctalia.conf` (+ qt5ct + gtk
   css) on every resolve, no network.
2. qt6ct with `color_scheme_path` → a NONEXISTENT file returns the fallback =
   the system/Fusion default palette (un-themed), never a crash. So the only
   un-themed window is before Noctalia's daemon first applies (a boot race).
3. Cleanest KDE-app theming under bare wlroots: on a PURE compositor, enable the
   `kcolorscheme` template (writes `kdeglobals`, offline, full KColorScheme) —
   safe with no Plasma session. `qt6ct-kde` gives KColorScheme reading with only
   KF6 libs (NOT plasma-workspace); `plasma-integration` (QPA=kde) is heaviest;
   Kvantum is a fragile style-only path.
4. Every serious project uses the same qtct custom-palette bridge (caelestia is
   near-identical to Noctalia); Kvantum is being abandoned (end-4 → qtengine);
   `kdeglobals` is the only full-KColorScheme route but is the shared-file leak.
5. Qt6 suffices for Dolphin/Gwenview/Kate/pcmanfm-qt in 2025/2026 (all Qt6);
   qt5ct only needed for specific Qt5 holdouts (Noctalia already writes a qt5ct
   scheme for free).
6. Bottom line: keep ADR 0102/0104's qtct bridge; make the default palette
   offline-deterministic (builtin source, or seed the community JSON at
   install) and optionally pre-seed a static noctalia.conf to close the boot
   race; turn `kcolorscheme` back ON only on pure-compositor boxes; keep
   combined boxes isolated (kcolorscheme OFF, kdeglobals Plasma-only).
   Per-session `XDG_CONFIG_HOME` fully isolates kdeglobals but is heavyweight —
   reserve it for a future hard KColorScheme-fidelity requirement.

---

## Q1 — Does Noctalia write templates offline for a builtin palette?

**YES — a builtin (and the builtin *fallback*) renders every template with
ZERO network. Offline apps are themed with the builtin palette, NOT left
unthemed.** Noctalia is now a compiled C++ app (repo restructured; `src/theme/`,
HEAD `4ea0a7f0`, 2026-09-04). Evidence traced through the source:

**Builtin palettes are compiled into the binary** — no fetch, ever.
`src/theme/builtin_palettes.cpp` hardcodes 10 palettes as `constexpr`
`kPalettes`: Ayu, **Catppuccin**, Dracula, Eldritch, Gruvbox, Kanagawa,
Noctalia, Nord, **Rosé Pine**, Tokyo-Night (each with full dark/light + ANSI
terminal colors). `findBuiltinPalette("Catppuccin")` returns it with no I/O.

**Community palettes are network-fetched + cached, but the resolver always
falls back to builtin on a miss.** `src/theme/theme_service.cpp`
`resolveAndSet()`:
- `source == Community`: looks for
  `$XDG_STATE_HOME/community-palettes/<url-encoded-name>.json` (note: **state
  dir**, not cache — see `communityPaletteCacheDir()` in
  `community_palettes.cpp`). If present+valid it resolves from cache and only
  re-downloads when the catalog md5 differs; if absent it calls
  `startCommunityDownload()` (async, fails silently offline).
- Catalog URL `https://api.noctalia.dev/palettes`, palette URL base
  `https://api.noctalia.dev/palette/<name>` (`community_palettes.cpp`).
- **Crucial fallback line:** after the source switch,
  `if (!resolved.has_value()) resolved = resolveBuiltin(cfg, mode, shellMode);`
  So an offline first boot with `source="community"` and empty cache resolves
  the **builtin** named by `[theme].builtin` (here `Catppuccin`, dark→Mocha).
  `resolveBuiltin` itself falls back again to `"Noctalia"` if the builtin name
  is unknown. **A resolved theme is ALWAYS produced.**

**Every resolve applies the templates.** The resolved palette flows
`ThemeService::resolvedCallback` →
`application_services.cpp:661 m_templateApplyService.apply(generated, ...)`.
So templates are (re)written on every palette resolution, including the offline
builtin-fallback path. `noctalia msg color-scheme-set <source> <name>` (CLI,
`schema_msg.h:359`) just writes source+selection into settings.toml and triggers
the same `resolveAndSet` → apply chain; for a builtin it is fully offline.

**What the qt/gtk templates write (all offline, from `assets/templates/` +
`builtin.toml` output_path):**
- `qt` → writes to **BOTH** `$XDG_CONFIG_HOME/qt5ct/colors/noctalia.conf`
  **and** `$XDG_CONFIG_HOME/qt6ct/colors/noctalia.conf` (a `[ColorScheme]`
  file with `active_colors=/inactive_colors=/disabled_colors=` QPalette lists).
  No `post_hook`, no network.
- `gtk3` → `$XDG_CONFIG_HOME/gtk-3.0/noctalia.css`; `gtk4` →
  `gtk-4.0/noctalia.css`. `post_hook gtk/apply.sh <mode>` appends
  `@import url("noctalia.css");` into `gtk.css` (idempotent), and best-effort
  `gsettings/dconf set gtk-theme adw-gtk3-dark + color-scheme prefer-dark`
  ONLY if the `adw-gtk3-dark` theme exists on disk and a schema/dconf is present
  (graceful no-op on a bare wlroots box with no gsettings schema).
- `kcolorscheme` → `$XDG_DATA_HOME/color-schemes/noctalia.colors` **plus**
  `post_action = "kde-color-scheme"`, which `src/theme/kde_color_scheme.cpp`
  `applyKdeColorScheme()` implements as: parse the `.colors`, **merge its groups
  into `$XDG_CONFIG_HOME/kdeglobals`** (`mergeKdeColorScheme`, atomic write),
  then emit the `org.kde.KGlobalSettings` D-Bus `notifyChange` signal. **This is
  exactly the `kdeglobals` mutation ADR 0104 dropped** by removing `kcolorscheme`
  from `builtin_ids`.

**Gate:** a template only runs if its id is in
`[theme.templates].builtin_ids`. This repo's `config.toml` lists
`qt, gtk3, gtk4` (+ terminals/compositor) but deliberately **omits
`kcolorscheme`** (ADR 0104), so qt6ct/qt5ct/gtk colors are written and
`kdeglobals` is left untouched.

**Bottom line for Q1:** the ADR 0101 phrasing "first boot needs network … shows
a fallback palette until it can fetch" is accurate but the fallback is the
compiled **builtin** (Catppuccin Mocha), not "unthemed". Qt6/GTK apps ARE fully
themed offline; they just show builtin-Catppuccin colors, which cross-fade to
the community "Catppuccin Mocha Lavender" tint once api.noctalia.dev is reached
and the palette re-resolves. Setting `source="builtin"` would be byte-for-byte
offline with no network dependency at all.

## Q2 — qt6ct color_scheme_path -> nonexistent file: what renders?

**It renders the DEFAULT system palette (Fusion's default light palette), NOT
the custom colors and NOT a crash.** Traced in upstream qt6ct source
(`trialuser02/qt6ct`, which qt6ct-kde forks):

- `qt6ctplatformtheme.cpp` `applySettings()` reads `color_scheme_path` +
  `custom_palette`. Only if `custom_palette==true` and path non-empty does it
  call `m_palette = loadColorScheme(resolvePath(schemePath),
  *QPlatformTheme::palette(SystemPalette))` — passing the **system palette as
  the fallback argument**.
- `qt6ct.cpp` `loadColorScheme(filePath, fallback)`: opens `filePath` as a
  `QSettings` INI. **A nonexistent file yields empty `active_colors` /
  `inactive_colors` / `disabled_colors` lists (count 0).** The guard
  `if (active >= NColorRoles && inactive >= … && disabled >= …)` fails, so it
  hits `else { customPalette = fallback; }` and returns the fallback
  unchanged. The same fallback path fires for a malformed/short scheme.
- Back in the theme, `m_palette` therefore holds the system palette; and if
  the whole `if` was skipped, `applySettings()` later does
  `if(!m_palette) m_palette = qApp->style()->standardPalette();`. With
  `style=Fusion` (as in this repo's `qt6ct.conf`) that is **Fusion's built-in
  default palette — the light/near-white default**, i.e. an un-themed app.

**Implication for the pre-seed:** the stow'd `qt6ct.conf` points
`color_scheme_path` at `~/.config/qt6ct/colors/noctalia.conf`, a file Noctalia
does not write until its theme service first applies templates. **Any Qt6 app
launched before Noctalia's daemon has applied (e.g. a very early autostart, or
if Noctalia is not running at all) shows default Fusion, not the palette.** Once
Noctalia writes `noctalia.conf` (offline builtin fallback per Q1), newly-launched
Qt apps pick it up. qt6ct installs a `QFileSystemWatcher` on the qt6ct config
**directory** (`createFSWatcher`, watches `Qt6CT::configPath()`) and re-applies
on change, but it watches the top-level dir; a write into the `colors/`
subdirectory is not guaranteed to fire a live re-apply for already-running apps,
so the reliable update point is next app launch. Net: the design is only
un-themed in the narrow window before Noctalia first runs — not offline per se.

## Q3 — Minimal way to theme KDE-framework apps under bare wlroots

Goal: give Dolphin/Gwenview/Kate the chosen palette with NO Plasma session.
Four mechanisms, grounded in Arch Wiki *Qt* / *Uniform look…* / *Kvantum* and
the qt6ct sources:

**(a) kcolorscheme template -> `~/.config/kdeglobals`.**
Noctalia's `kcolorscheme` template writes
`$XDG_DATA_HOME/color-schemes/noctalia.colors` then its `post_action
"kde-color-scheme"` (`kde_color_scheme.cpp::applyKdeColorScheme`) **merges the
scheme into `~/.config/kdeglobals`** and fires the `KGlobalSettings` D-Bus
signal. This is the *canonical* KDE mechanism and gives the FULL KColorScheme
color set (the many extended roles KDE-framework apps read). Needs: nothing
beyond the KF6 apps themselves; `kdeglobals` is read natively. **Trade-off / why
this repo rejects it (ADR 0104):** `kdeglobals` is a single global file Plasma
ALSO owns, so on a combined kde+compositor box it repaints the next Plasma
session non-Breeze — the cross-session leak. Fine on a pure compositor, toxic on
a combined box.

**(b) qt6ct-kde's "noctalia (KColorScheme)" scheme option.**
Arch *Qt*: `qt5ct-kde`/`qt6ct-kde` "provide patched qt5ct/qt6ct with better
integration to KDE applications, including KDE QML applications and **can read
and apply KColorSchemes**." In qt6ct-kde you pick a `.colors` scheme (shown as
`… (KColorScheme)`) and it builds the extended KDE palette and pushes it to KDE
apps via the platform theme — WITHOUT writing `kdeglobals`. Per Noctalia docs
you then "select `noctalia (KColorScheme)` or `noctalia`". **Caveat for this
repo:** the `(KColorScheme)` entry only appears if a `noctalia.colors` file
exists in a `color-schemes/` dir — which is produced by the very `kcolorscheme`
template ADR 0104 dropped. So on this repo only the plain **`noctalia`** entry
(custom_palette from `qt6ct/colors/noctalia.conf`) is available; KDE apps get
Noctalia's base QPalette but lose the KColorScheme-specific accent roles. That
is exactly the "narrow, bounded cost" ADR 0104 accepts.
Install cost: `qt6ct-kde` → `qqc2-desktop-style` → `kcolorscheme, kconfig,
kirigami, sonnet` (KF6 libs) — **but NOT `plasma-workspace`/`plasma-integration`**
(verified via `pactree`). So it is the *light* KColorScheme path.

**(c) plasma-integration platform theme (`QT_QPA_PLATFORMTHEME=kde`).**
Arch *Qt*: the KDE QPA lives in `plasma-integration`, "pulled by
`plasma-workspace`." It reads `kdeglobals` and gives the fullest, most native
KDE styling. **Trade-off:** it drags in `plasma-workspace` (a large Plasma
dependency) onto an otherwise-bare wlroots box, and still keys off the shared
`kdeglobals`. Heaviest option; over-kill for "just theme Dolphin".

**(d) Kvantum (`kvantum`, `QT_STYLE_OVERRIDE=kvantum`).**
Arch *Kvantum*: an SVG **style** (not a platform theme); "works as a Qt style
instead of a Qt platform theme." Set it via qt6ct's Style dropdown or the env
var. It controls widget *look* and can carry colors, but Arch/end-4 field
reports show **many Qt apps ignore Kvantum colors** (worked in Dolphin/Kate,
not in KDE Connect / System Monitor / Haruna), often needing
`qqc2-desktop-style`. It does not by itself feed the KColorScheme roles. Extra
moving part; not needed when qt6ct already sets the palette.

**Minimal recommendation for a PURE compositor (no Plasma):** option (a) —
enable `kcolorscheme`, let it write `kdeglobals` — is the smallest, most native
way to fully theme Dolphin, and is SAFE there because no Plasma session shares
the file. On a COMBINED box, fall back to (b): `qt6ct-kde` with the plain
`noctalia` custom palette (this repo's choice), accepting the loss of extended
KColorScheme accent roles, to keep `kdeglobals` Plasma-only.

## Q4 — How comparable projects do it

- **Noctalia (own docs + source).** Template processor renders `{{colors.*}}`
  into `qt5ct+qt6ct/colors/noctalia.conf` (custom_palette, Fusion),
  `gtk-{3,4}.0/noctalia.css` (@import'd into `gtk.css`), and optionally
  `color-schemes/noctalia.colors` + `kdeglobals` merge. Env
  `QT_QPA_PLATFORMTHEME=qt6ct`; package `qt6ct-kde` + `adw-gtk-theme`. Enable
  templates in Settings → Templates; pick `noctalia`/`noctalia (KColorScheme)`
  in qt6ct. Docs: docs.noctalia.dev/…/templates/official/gtk-qt.

- **caelestia-dots/qt (`caelestia install qt`).** Nearly IDENTICAL to Noctalia:
  a `qtct.conf` template with `color_scheme_path -> colors/caelestia.conf`,
  `custom_palette=true`, `style=Fusion`, `icon_theme=Papirus-{mode}`; the CLI
  `apply_qt` writes BOTH `qt5ct/colors/caelestia.conf` and
  `qt6ct/colors/caelestia.conf`, then rewrites `qt{5,6}ct.conf`. Depends on
  `qt5ct-kde`+`qt6ct-kde`+`adw-gtk-theme`. Live updates via an `inotifywait`
  monitor (systemd unit). Uses the Darkly style for widgets. This corroborates
  Noctalia's design as the field-standard "qtct custom-palette" pattern.
  (github.com/caelestia-dots/qt)

- **end-4/dots-hyprland (illogical-impulse).** Wallpaper → Material You via
  `kde-material-you-colors`; historically routed Qt through **Kvantum**
  (`materialadw` theme) selected in qt6ct + `QT_QPA_PLATFORMTHEME=qt5ct`, with
  KDE apps set via `kcmshell6 kcm_style/kcm_colors`. Known pain: many Qt apps
  ignore Kvantum colors; fixes need `qqc2-desktop-style`. The project has been
  **migrating away from Kvantum toward `qtengine`/`qt6ct` custom palettes** (Disc
  #3182) — a matugen qt template emitting `color-schemes/matugen.colors` +
  `QT_QPA_PLATFORMTHEME=qtengine`. Trend is AWAY from Kvantum, TOWARD
  qtct/qtengine custom palettes. (github.com/end-4/dots-hyprland PR #1055,
  Disc #3182)

- **ML4W (mylinuxforwork/dotfiles).** Qt theming is NOT auto-driven by the
  wallpaper palette; it ships `qt6ct` for Qt6 and leaves color-following to the
  user (dark mode via qt6ct + breeze/Kvantum). Its automated switcher targets
  GTK + Waybar. So ML4W is the *weakest* Qt-follows-shell integration of the
  four. (ml4w.com/os/help/troubleshooting)

- **JaKooLit/Hyprland-Dots (adjacent).** `DarkLight.sh` `sed`-rewrites the
  `color_scheme_path` line in `qt5ct.conf`/`qt6ct.conf` (Catppuccin-Mocha.conf
  ↔ Latte.conf) and swaps the Kvantum theme on mode toggle; env
  `QT_QPA_PLATFORMTHEME=qt6ct` + `QT_STYLE_OVERRIDE=kvantum`.

**Cross-project consensus:** the durable mechanism is a **qtct custom-palette**
(`custom_palette=true`, `color_scheme_path` → a generated
`colors/<name>.conf`, `style=Fusion`) written for BOTH qt5ct and qt6ct, plus
`QT_QPA_PLATFORMTHEME=qt6ct` (or `qtengine`); GTK via `adw-gtk3` + generated
`@import` CSS. Kvantum is the older/fragile path being abandoned. `kdeglobals`
is the only route to the FULL KColorScheme set but is the shared-file leak.

## Q5 — Is Qt5/qt5ct still needed in 2025/2026?

**Mostly no for a modern Arch box, but not zero.** As of 2025/2026:
- KDE Frameworks 6 / Plasma 6 (Qt6) is the default everywhere on Arch; the KDE
  apps this task cares about — **Dolphin, Gwenview, Kate are Qt6/KF6**. This
  repo's file manager `pcmanfm-qt` depends on `libfm-qt6` → **Qt6 only**
  (verified: `pcmanfm-qt` → `libfm-qt6.so`). So the base preset needs only Qt6.
- Arch *Qt* notes Qt6 apps "should not pose a problem" and that the KDE QPA is
  `plasma-integration` for Qt6. `QT_QPA_PLATFORMTHEME=qt6ct` covers Qt6.
- **Remaining Qt5 holdouts** (need `qt5ct`/`qt5ct-kde` + a Qt5 palette to be
  themed): apps still on Qt5 in 2025 — e.g. some older/AUR KDE5 apps, a few
  proprietary/Qt5-linked tools, and libraries pinned to Qt5 widgets. The Gentoo
  forum thread in the search corpus documents the transition friction where Qt6
  stopped honoring qt5ct. For a stock Arch wlroots setup with modern apps, Qt5
  is an edge case.
- Notably Noctalia's `qt` template AND caelestia BOTH still write the
  `qt5ct/colors/<name>.conf` output alongside qt6ct "for free" — so Qt5 apps
  are covered IF the user also installs `qt5ct`/`qt5ct-kde` and sets
  `QT_QPA_PLATFORMTHEME=qt6ct` (Qt5 apps auto-use qt5ct when both present, or
  set `=qt5ct` explicitly). This repo installs only `qt6ct-kde` per ADR 0102
  ("Qt5 is out — no Noctalia template"), which is defensible for a modern
  toolchain; the moment a Qt5 app is added, `qt5ct`+the already-generated
  `qt5ct/colors/noctalia.conf` would theme it with no template change.

**Verdict:** Qt6 is sufficient for the stated apps (Dolphin/Gwenview/Kate/
pcmanfm-qt) in 2025/2026; qt5ct is only worth adding if a specific Qt5 holdout
is installed.

## Q6 — Bottom line: cleanest offline-safe design

### Shared invariants (both box types)
- Keep `QT_QPA_PLATFORMTHEME=qt6ct` per-compositor (niri `environment{}`,
  Hyprland `env=`), as ADR 0102 already does — env.d misses start-hyprland.
- Keep the stow'd `qt6ct.conf` (`custom_palette=true`, `style=Fusion`,
  `color_scheme_path=~/.config/qt6ct/colors/noctalia.conf`). It is compositor-
  private (Plasma never reads it) so it is safe to share (ADR 0104).
- Keep `qt` + `gtk3` + `gtk4` in Noctalia `builtin_ids`; GTK via
  `adw-gtk3-dark` + `@import noctalia.css`.

### OFFLINE-SAFE first boot — the one concrete fix
The ONLY genuine offline gap (per Q1+Q2) is: `source="community"` means first
boot with no network renders the **builtin Catppuccin fallback**, and worse,
Qt apps launched *before Noctalia's daemon first applies* see default Fusion
(Q2). To make offline first boot deterministic and palette-correct:

1. **Prefer `source="builtin"` (builtin `Catppuccin`, mode dark) as the shipped
   default**, OR pre-seed the community palette JSON into
   `$XDG_STATE_HOME/community-palettes/<url-encoded-name>.json` at install time
   (the installer already fetches plugins at build; it can fetch+seed the one
   palette too). Either makes the daemon resolve the intended palette with zero
   network — no builtin→community cross-fade, no api.noctalia.dev dependency.
   This directly answers ADR 0101's "offline-first ever matters" note; the
   builtin `Catppuccin` is not identical to the community "Mocha Lavender"
   accent, so seed the JSON if the exact lavender accent must survive offline.
2. **Optionally pre-seed a static `qt6ct/colors/noctalia.conf`** (a snapshot of
   the builtin/community palette) into `/etc/skel` so even a Qt app launched
   in the sub-second before Noctalia applies gets the palette, not Fusion.
   Noctalia overwrites it on first apply, so it self-heals to live-following.
   (Trade-off: reintroduces a static file ADR 0102 removed — keep it clearly
   labelled "seed, overwritten by Noctalia".)

Note the qt template already writes offline; the seed only covers the boot-race
window and the community-accent-offline case.

### Pure-compositor (no-KDE) box
- Add `kcolorscheme` back to `builtin_ids` **conditionally, only when the KDE
  adapter did NOT run**. On a pure compositor there is no Plasma session to
  leak into, so writing `kdeglobals` + `color-schemes/noctalia.colors` is safe
  and gives Dolphin/Gwenview/Kate the FULL KColorScheme palette (option Q3a) —
  strictly better than the base-QPalette-only result. Fully offline (no network
  in the kcolorscheme path).
- Result: GTK (adw-gtk3 + noctalia.css), plain Qt (qt6ct custom palette), and
  KDE apps (kdeglobals) all follow Noctalia, offline, on one box.

### Combined kde+compositor box
- Keep ADR 0104 as-is: **`kcolorscheme` OFF**, `kdeglobals` stays Plasma-only,
  KDE apps under the compositor get Noctalia's base palette via `qt6ct-kde`'s
  plain `noctalia` scheme (losing only extended KColorScheme accents). Plasma
  session stays Breeze. This is the correct, minimal isolation.

### Per-session XDG_CONFIG_HOME isolation — assessment
- It is the ONLY mechanism that *fully* isolates `kdeglobals` so BOTH a Breeze
  Plasma session AND a Catppuccin `kcolorscheme` compositor session can
  coexist with full KColorScheme theming in each. Mechanically: launch each
  session with a distinct `XDG_CONFIG_HOME` (e.g.
  `~/.config` for Plasma, `~/.config-compositor` for niri/Hyprland), so each
  gets its own `kdeglobals`, `qt6ct.conf`, `gtk` files.
- **Assessment: viable but heavy, and NOT recommended as default.** Costs:
  (a) every app's config now forks per session — anything the user tweaks in
  one session is invisible in the other (surprising, support burden);
  (b) many tools assume the default `~/.config` and some hardcode it;
  (c) the installer/stow/skel model (which targets `~/.config`) must be
  duplicated or symlink-merged per session;
  (d) ADR 0104's own survey found it "documented-yet-unshipped folklore." The
  payoff (extended KColorScheme accents in KDE apps opened under a compositor
  on a combined box) is the exact narrow case ADR 0104 already judges
  low-value. **Conclusion: only worth it if full KColorScheme fidelity in BOTH
  sessions becomes a hard requirement; otherwise the conditional-kcolorscheme
  split above is the clean, low-cost answer.** If ever shipped, scope it to
  only the divergent files via a symlink farm (share everything, fork only
  `kdeglobals` + the gtk `settings.ini`) rather than a full second config tree.

### One-line bottom line
Ship the qtct custom-palette bridge exactly as ADR 0102/0104 have it, but
(1) make the default palette offline-deterministic (builtin source, or seed the
community JSON) and (2) turn `kcolorscheme` back ON *only* on pure-compositor
boxes — leaving combined boxes isolated. Per-session `XDG_CONFIG_HOME` is a real
but heavyweight escape hatch reserved for a future hard KColorScheme-fidelity
requirement.

## Sources (primary)

Noctalia source (github.com/noctalia-dev/noctalia-shell, HEAD `4ea0a7f0`,
2026-09-04; cloned + read directly):
- `src/theme/builtin_palettes.cpp` — 10 compiled-in palettes (Catppuccin, Rosé
  Pine, …), fully offline.
- `src/theme/community_palettes.cpp` — `api.noctalia.dev/palettes` catalog +
  `/palette/<name>`, cached under `$XDG_STATE_HOME/community-palettes/`.
- `src/theme/theme_service.cpp` `resolveAndSet()` — source switch +
  `if(!resolved) resolveBuiltin(...)` offline fallback.
- `src/app/application_services.cpp:661` — `m_templateApplyService.apply(...)`
  on every resolve.
- `src/theme/template_apply_service.cpp`, `src/cli/schema_msg.h:359`
  (`color-scheme-set`), `src/theme/kde_color_scheme.cpp`
  (`applyKdeColorScheme` → merges into `~/.config/kdeglobals` + KGlobalSettings
  D-Bus notify).
- `assets/templates/builtin.toml` — template output paths (qt →
  qt5ct+qt6ct/colors/noctalia.conf; gtk3/4 → noctalia.css; kcolorscheme →
  color-schemes/noctalia.colors + post_action kde-color-scheme).
- `assets/templates/qt/qtct.conf`, `assets/templates/qt/undo.sh`,
  `assets/templates/gtk/apply.sh`, `assets/templates/gtk/gtk3.css`.

qt6ct source (github.com/trialuser02/qt6ct, forked by qt6ct-kde; cloned + read):
- `src/qt6ct-qtplugin/qt6ctplatformtheme.cpp` `applySettings()` — reads
  `color_scheme_path`+`custom_palette`, fallback to SystemPalette /
  `style->standardPalette()`; `createFSWatcher` on config dir.
- `src/qt6ct-common/qt6ct.cpp` `loadColorScheme()` — nonexistent/short file →
  returns the `fallback` palette.

Arch Wiki (fetched via `index.php?action=raw`, Anubis-gated for the HTML view):
- *Uniform look for Qt and GTK applications* — qt6ct-kde/qt5ct-kde for Breeze
  on Qt outside Plasma; Kvantum is a style not a platform theme;
  `QT_QPA_PLATFORMTHEME=gtk3/gtk2/kde`.
- *Qt* — "Configuration of Qt 5/6 applications under environments other than KDE
  Plasma"; qt6ct-kde "can read and apply KColorSchemes"; KDE QPA =
  `plasma-integration` pulled by `plasma-workspace`.

Noctalia docs: docs.noctalia.dev/noctalia/templates/official/gtk-qt/ — required
packages (`adw-gtk-theme`, `qt6ct-kde`), env var, "select `noctalia
(KColorScheme)` or `noctalia`".

Comparable projects: github.com/caelestia-dots/qt (identical qtct custom-palette
pattern, qt5ct+qt6ct); github.com/end-4/dots-hyprland PR #1055 + Disc #3182
(Kvantum → qtengine migration); ml4w.com/os/help/troubleshooting (Qt not
auto-driven); JaKooLit/Hyprland-Dots DeepWiki (sed-rewrite color_scheme_path).

Local system facts (`pacman`/`pactree`): `qt6ct-kde 0.11-8` → `qqc2-desktop-
style` → `kcolorscheme`+KF6 libs, **not** `plasma-workspace`; `pcmanfm-qt` →
`libfm-qt6` (Qt6).

## Caveat / drift note
This box still has the 14 static `catppuccin-mocha-*.conf` files under
`.config/qt6ct/colors/` (stow'd), which ADR 0102 said were removed — a repo
drift, not central to this research but worth a cleanup check.

---

## Q7 — dark/light following on COMBINED boxes (no kdeglobals color leak)

Narrow goal: KDE-framework apps (Dolphin/Gwenview/Kate) launched UNDER the
compositor should follow Noctalia's DARK/LIGHT mode, without writing colors into
the shared `~/.config/kdeglobals` (ADR 0104). Traced through KColorScheme,
qt6ct-kde, and Qt sources.

### 1. Do KF6/KColorScheme apps outside Plasma follow the portal light/dark?
**YES — via `KColorSchemeManager` in "automatic" mode, which reads the Qt
`styleHints()->colorScheme()` (the org.freedesktop.appearance portal value) and
picks BreezeDark vs BreezeLight, reacting live — with NO kdeglobals color write.
But it is opt-in per app and has strict conditions.** Evidence from KColorScheme
source (github.com/KDE/kcolorscheme, `src/kcolorschememanager.cpp`):
- `automaticColorSchemeId()`:
  `if (qGuiApp->styleHints()->colorScheme() == Qt::ColorScheme::Dark) return
  getDarkColorScheme(); return getLightColorScheme();` — i.e. Breeze
  Dark/Light chosen purely from the Qt color-scheme hint.
- `KColorSchemeManager::init()` connects
  `QStyleHints::colorSchemeChanged → schemeChanged`, which re-runs
  `activateSchemeInternal(automaticColorSchemePath())` — so it flips live on a
  portal change, **and writes nothing to kdeglobals** (automatic mode only calls
  `qApp->setPalette(...)`).
- **Conditions for automatic mode (all from `automaticColorSchemeId()` /
  `init()`):** (a) no scheme saved in kdeglobals `[UiSettings] ColorScheme`
  (a manual pick pins it and disables following — note this is `[UiSettings]`,
  a *different* key from Plasma's `[General] ColorScheme`+`[Colors:*]`);
  (b) `isKdePlatformTheme()` is false (platform theme name != "kde", and not
  xdgdesktopportal-under-XDG_CURRENT_DESKTOP=KDE) — true on a bare wlroots box
  with `QT_QPA_PLATFORMTHEME=qt6ct`; (c) the app property
  `KDE_COLOR_SCHEME_PATH` is empty (if a platform theme pins a scheme path,
  automatic mode defers to it and returns empty); (d) not HighContrast.
- **Caveat 1 — opt-in:** `KColorSchemeManager` is a singleton created via
  `instance()`; it is not force-run for every KF6 app. It is active when an app
  offers the standard color-scheme menu (`KColorSchemeMenu::createMenu`) or
  otherwise instantiates it. KColorScheme itself (the palette-builder) does NOT
  poll the portal; the manager does. So an app that never touches the manager
  gets no automatic following.
- **Caveat 2 — version:** KColorScheme's non-KDE-platformtheme path was only
  reliably fixed in **6.20.0** ("Fix colors in kdeglobals not being respected
  when platformtheme is not kde"). This box has `kcolorscheme 6.29.0` — fine.

### 2. Does Qt 6.5+ auto-follow the portal for the base palette, and does qt6ct pass it through?
- Qt 6.5 introduced `Qt::ColorScheme` + `QStyleHints::colorScheme` +
  `colorSchemeChanged`; on Linux the value comes from the XDG portal
  `org.freedesktop.appearance / color-scheme` (0 none / 1 dark / 2 light). Later
  Qt (6.7+) has `QGenericUnixTheme` monitor that portal signal directly;
  *manually* setting the scheme is only implemented in the KDE/GTK3 platform
  themes (picked to 6.9), not the bare generic theme.
- **qt6ct passes the color-scheme hint through** (does NOT override it): its
  `Qt6CTPlatformTheme::themeHint()` switch has no color-scheme case and falls to
  `default: return QGenericUnixTheme::themeHint(hint)` (verified in
  `qt6ctplatformtheme.cpp`). So the portal-driven `styleHints()->colorScheme()`
  reaches the app — which is exactly what KColorSchemeManager consumes.
- **But qt6ct's `custom_palette=true` overrides the *base* QPalette** with the
  single Noctalia palette from `noctalia.conf`; it does not itself produce
  separate light/dark from the hint. So **plain-Qt apps follow mode because
  Noctalia rewrites `noctalia.conf` per mode** (as already known), while the
  color-scheme *hint* still propagates for KColorScheme's benefit.
- **qt6ct-kde interaction:** the installed plugin
  (`/usr/lib/qt6/plugins/platformthemes/libqt6ct.so`) references
  `isKColorScheme` + `KDE_COLOR_SCHEME_PATH`. When the selected
  `color_scheme_path` is a KColorScheme `.colors` file it sets
  `KDE_COLOR_SCHEME_PATH` (pinning a fixed scheme → KColorSchemeManager stops
  auto-following). With this repo's PLAIN `noctalia.conf` (not a `.colors`,
  `isKColorScheme` false) it does **not** pin a path, so `KDE_COLOR_SCHEME_PATH`
  stays empty and KColorSchemeManager's automatic light/dark following remains
  active. This is the favorable case for the narrow goal.

### 3. Lightest way to flip KDE-app light/dark with no persistent kdeglobals leak
**Lightest = the portal chain, which writes ZERO to kdeglobals** and is not even
one of the three listed options:
`Noctalia gtk/apply.sh → gsettings org.gnome.desktop.interface color-scheme
prefer-{dark,light}` → **xdg-desktop-portal-gtk** reads that GSettings key and
republishes it as `org.freedesktop.appearance color-scheme` → Qt
`styleHints()->colorScheme()` → `KColorSchemeManager` (automatic) → BreezeDark ↔
BreezeLight. Requirements, all already met on this box: `xdg-desktop-portal` +
`xdg-desktop-portal-gtk` installed (1.22.1 / 1.15.3) to serve the appearance
namespace on a bare wlroots session; `kcolorscheme ≥ 6.20` (6.29 here); plain
`noctalia` qt6ct scheme (no `.colors` pin); no `[UiSettings] ColorScheme` saved.
It works only for apps that activate `KColorSchemeManager`; others fall back to
the seeded Breeze variant (option c below).

Assessing the listed options:
- **(a) write only `[General] ColorScheme=BreezeDark/Light` to kdeglobals** —
  rejected. It is still a live write to the Plasma-shared file (the exact ADR
  0104 prohibition), and it does not even drive KColorSchemeManager, which reads
  `[UiSettings] ColorScheme`, not `[General]`. Writing `[UiSettings] ColorScheme`
  instead would *pin* the scheme and DISABLE automatic following. Self-healing
  is not guaranteed: Plasma re-asserts its scheme on login only when its
  look-and-feel/kcm specifies one, and a running Plasma session could repaint
  from the change. Net: shared-file mutation + wrong key + kills auto-follow.
- **(b) per-session `XDG_CONFIG_HOME` for kdeglobals only** — works but
  heavyweight (see Q6); massive overkill when the goal is merely light/dark.
- **(c) accept the seeded Breeze variant (ADR 0088 = Breeze Dark), only
  plain-Qt/GTK follow mode** — the safe zero-effort fallback for apps that do
  not use KColorSchemeManager. Combined with the portal chain it degrades
  gracefully: apps that use the manager follow mode, the rest stay Breeze Dark.

**Recommendation:** ensure a portal backend serving `org.freedesktop.appearance`
is present in the compositor session (xdg-desktop-portal-gtk) and rely on the
gsettings→portal→KColorSchemeManager chain — it flips KDE apps light/dark with
NO kdeglobals write. Accept (c) as the fallback for non-manager apps. Do not use
(a); reserve (b) for a future full-color (not just mode) KColorScheme fidelity
requirement.

### 4. What Noctalia's gtk/apply.sh sets, and does it emit an appearance signal?
Confirmed from `assets/templates/gtk/apply.sh` (`sync_system_appearance`):
per mode it runs `gsettings set org.gnome.desktop.interface color-scheme
prefer-$mode` (and `gtk-theme adw-gtk3[-dark]` only if that theme exists on
disk), with a `dconf write /org/gnome/desktop/interface/color-scheme
'prefer-$mode'` fallback, and a clean no-op if neither gsettings nor dconf nor a
schema is present. **It does NOT emit any `org.freedesktop.appearance` signal
itself and runs no portal** — it only writes the GSettings key; publishing the
appearance preference is left to a portal backend (xdg-desktop-portal-gtk) that
reads that GSettings key. So on a bare wlroots box the KDE-app light/dark chain
depends on that portal backend being installed and running in the session.
