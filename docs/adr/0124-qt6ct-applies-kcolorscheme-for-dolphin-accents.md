# qt6ct-kde applies Noctalia's KColorScheme so KColorScheme apps follow accents

---
Status: accepted. **Fixes a gap in ADR 0123** (and corrects ADR 0116's live-
repaint claim). ADR 0123 merged the palette into `kdeglobals` to make
KColorScheme apps (Dolphin/Gwenview/Kate) follow Noctalia under a compositor —
but they only followed the **base** palette (window/view), while accent roles
(selection, focus, header) stayed **Breeze**. Traced + fixed live on the fresh
`arch-combined` VM with screenshots + pixel sampling.
---

Under a compositor, Qt apps use `QT_QPA_PLATFORMTHEME=qt6ct` (ADR 0102). The
seeded `qt6ct.conf` pointed `color_scheme_path` at `qt6ct/colors/noctalia.conf`
— a qt6ct **QPalette** file (`active_colors=…`). qt6ct-kde's
`Qt6CT::isKColorScheme()` returns false for that format, so it applies only a
QPalette and lets each KColorScheme app fall back to the **default Breeze**
KColorScheme for its accent roles. Result on the VM: Dolphin's window/view
backgrounds followed the palette (via the QPalette) but its selection highlight
rendered Breeze-blue for **every** palette — neither `kdeglobals` (ADR 0123) nor
the qt6ct QPalette reached the KColorScheme roles. `kdeglobals` isn't consulted
because qt6ct-kde, as the platform theme, supplies the KColorScheme itself.

Noctalia's `kcolorscheme` template (ADR 0123, now fleet-wide) **also** writes a
real KColorScheme file: `~/.local/share/color-schemes/noctalia.colors`
(`[Colors:*]` groups, `[WM]`, `[ColorEffects:*]`). qt6ct-kde *can* consume that
directly — `isKColorScheme()` → `KColorScheme::createApplicationPalette()` — and
apply the **full** scheme.

## Decision

1. **Point qt6ct at the `.colors` KColorScheme, not the QPalette `.conf`.** The
   seeded/stowed `qt6ct.conf` sets
   `color_scheme_path=~/.local/share/color-schemes/noctalia.colors`. qt6ct-kde
   detects the KColorScheme and applies it, so KColorScheme apps follow the
   palette's **accent** roles too, while plain-Qt apps (pcmanfm-qt) still get the
   derived QPalette. VM-verified across Gruvbox (olive selection) and the
   community Cherry Blossom (pink selection) for both Dolphin and pcmanfm-qt.

2. **Boot-race snapshot becomes a `.colors` file.** The preset seeds a static
   default-palette `noctalia.colors` into `/etc/skel/.local/share/color-schemes/`
   (replacing the old qt6ct QPalette snapshot) — themes the sub-second before
   Noctalia's first apply and creates the dir the bridge watches. Seed-only;
   Noctalia overwrites it on first apply.

3. **Live Theme Bridge watches `noctalia.colors`.** It adds
   `~/.local/share/color-schemes` (include `*.colors`) to its inotify set and
   `mkdir -p`s it, so a palette change nudges qt6ct and **plain-Qt** apps repaint
   live.

4. **KColorScheme apps are relaunch-only for palette** (corrects ADR 0116). VM-
   verified: neither the qt6ct nudge nor a `KGlobalSettings.notifyChange` D-Bus
   signal makes a **running** Dolphin re-read its KColorScheme — it caches it at
   startup. So a *freshly-launched* KColorScheme app follows the palette; an open
   one updates on relaunch — the same bounded cost GTK already has (ADR 0116).

## Considered options

- **Keep `kdeglobals` as the source (ADR 0123 alone)** — rejected: qt6ct-kde
  supplies the KColorScheme as platform theme, so `kdeglobals` never reaches
  KColorScheme apps under the compositor; only accents-via-Breeze resulted.
- **`KDE_COLOR_SCHEME_PATH` env, per-compositor** — rejected: it would leak into
  a same-boot Plasma session (the ADR 0122 class of bug) and force KDE apps onto
  Noctalia; `qt6ct.conf` is compositor-private (Plasma never reads it), so it
  keeps KDE isolated for free.
- **Chase KColorScheme live-repaint** (restart apps / a scheme-watching shim) —
  rejected as brittle/disproportionate; relaunch-only matches GTK and mode still
  follows.
- **Drop the qt QPalette template** now that `.colors` drives everything —
  deferred: it still triggers the bridge and is harmless; removing it is
  unrelated cleanup.

## Consequences

- **KColorScheme apps fully follow the Noctalia palette** under niri/Hyprland —
  backgrounds *and* accents — for every builtin/community/wallpaper/custom
  palette. ADR 0123's kdeglobals merge + KDE reset still stand (they keep KDE
  Breeze); this adds the qt6ct-kde path that actually themes Dolphin.
- **KDE stays Breeze** — the change is entirely in compositor-private
  `qt6ct.conf`; Plasma uses plasma-integration and never reads it (ADR 0104).
- **Live-repaint:** plain-Qt yes; KColorScheme + GTK relaunch-only (documented).
- The default palette now has its boot-race snapshot as `noctalia.colors`
  (a palette-sync point, replacing the qt6ct QPalette snapshot). Guarded by
  `noctalia-stow.bats`.
