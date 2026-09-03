# 02 — Qt/KDE apps follow Noctalia (App Theming Bridge: Qt path)

**What to build:** On a fresh install and on a freshly-stowed box, Qt6
applications and KColorScheme-consuming KDE apps render in the
[[Wayland Shell Companion]]'s live palette on **both** niri and Hyprland — on
first login, with zero GUI steps — and re-render when the Noctalia palette
changes. This is the Qt half of the [[App Theming Bridge]] (ADR 0102): ship the
Qt platform theme, point it at Noctalia's generated scheme, set the platform-theme
env var where both compositors can see it, and retire the hand-maintained static
color files that used to stand in for it.

Scope is Qt6 and KColorScheme (Noctalia's native templates). Qt5 and Kvantum are
out of scope.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `qt6ct-kde` (AUR) resolves as a fleet theming dependency under **kde, niri
      and hyprland** — declared in each wlroots adapter's `aur.theming`, unioned
      by the [[Package Resolver]] the same way the Bibata cursor is (ADR 0098) —
      no longer KDE-only. Reverses the qt6ct clause of ADR 0062 (per ADR 0102).
- [ ] A stow-owned `qt6ct.conf` pre-selects Noctalia's generated `noctalia`
      color scheme (`color_scheme_path` at `qt6ct/colors/noctalia.conf`,
      `custom_palette` on), so Qt is themed on first login without opening qt6ct.
- [ ] The 14 static `qt6ct/colors/catppuccin-mocha-*.conf` files are removed —
      Noctalia's `noctalia` scheme is the single source of Qt color.
- [ ] `QT_QPA_PLATFORMTHEME=qt6ct` is set per-compositor — in niri's
      `environment {}` and Hyprland's `env =` — never `environment.d` (Hyprland's
      `start-hyprland` session wouldn't see it; ADR 0070). Qt apps consult qt6ct
      on both compositors.
- [ ] Seam 1 (`noctalia-stow.bats`) asserts the `qt6ct.conf` pre-seed shape, the
      absence of the static `catppuccin-mocha-*.conf` files, and the
      per-compositor `QT_QPA_PLATFORMTHEME` env lines in `config.kdl` and
      `hyprland.conf`.
- [ ] Seam 2 (`profiles-aur.bats`) asserts `qt6ct-kde` resolves under kde, niri
      and hyprland (and not on a desktop-less host), replacing the old
      "kde-only / not under a non-kde DE" cases.
- [ ] The full installer test suite is green.
