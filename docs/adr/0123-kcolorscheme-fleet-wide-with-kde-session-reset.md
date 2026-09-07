# KColorScheme apps follow Noctalia everywhere; KDE self-resets on login

---
Status: accepted. **Supersedes ADR 0104/0108's combined-box `kcolorscheme`
drop** and **extends ADR 0116** (the combined-box KDE-login reset) and ADR 0122
(the Qt platform-theme un-leak). Goal: a cohesive Qt+GTK look that follows the
Noctalia palette on niri/Hyprland **including KColorScheme apps** (Dolphin/
Gwenview/Kate), with KDE staying Breeze. Traced + verified end-to-end on the
`arch-combined` VM (screenshots + pixel sampling).
---

ADR 0102 made GTK and plain-Qt apps follow Noctalia under a compositor, but
**KColorScheme apps read the shared `~/.config/kdeglobals`**, and ADR 0104
dropped Noctalia's `kcolorscheme` template on combined boxes (ADR 0108 re-enabled
it only on pure compositors) to keep Plasma's `kdeglobals` Breeze. So on a
combined box Dolphin rendered Breeze under the compositor — a visible break in
the otherwise-cohesive Noctalia look (VM: Dolphin all-Breeze while pcmanfm-qt and
GTK apps followed the palette). There is no per-session redirect for
`kdeglobals`; the only levers are "one shared file, login-time tug-of-war" or a
full `XDG_CONFIG_HOME` split (ADR 0104 rejected the latter as heavyweight).

ADR 0116 already proved the tug-of-war pattern is fine for the GTK theme: each
session reasserts its own state on login. The missing piece was extending that
to `kdeglobals` colours (and cursor).

## Decision

1. **Enable `kcolorscheme` on every Noctalia box** (combined included). The
   preset injects it into the **seeded** `config.toml` unconditionally (the
   committed shared file still ships without it, so a hand-stow with no installer
   never leaks). Under a compositor, Noctalia merges its palette into
   `kdeglobals`, so KColorScheme apps follow **any** active palette — the six
   builtins (Catppuccin, Dracula, Gruvbox, Kanagawa, Nord, Tokyo-Night),
   community, wallpaper and custom — palette-agnostic, live-repainting via the
   `KGlobalSettings` D-Bus notify Noctalia's `kde-color-scheme` post-action emits.

2. **Combined boxes seed a KDE session reset** (extends ADR 0116's GTK-only
   reset). A KDE-only autostart (`kde-session-reset.desktop`, `OnlyShowIn=KDE`,
   combined-box-gated) runs a fixed-path helper `/usr/local/bin/kde-session-reset`
   that, on Plasma login, reasserts: `gtk-theme=Breeze` + `color-scheme=
   prefer-dark` (GTK), `plasma-apply-colorscheme BreezeDark` (KColorScheme — the
   captured scheme's colours are byte-identical to stock BreezeDark), and the
   cursor. The live notify repaints already-open apps. The helper lives in
   `/usr/local/bin` — not a `$HOME` script the systemd XDG-autostart generator
   mangles (ADR 0116), and not an inline `Exec` (too complex to quote safely with
   the cursor read-back).

3. **Cursor: symmetric login-time reassert** of the shared `gsettings
   cursor-theme` (the layer KDE's cursor KCM rewrites; `XCURSOR_THEME` per-
   compositor already shields native + XWayland). The compositor autostarts
   reassert Bibata; the KDE reset reasserts the operator's KDE cursor **read from
   `kcminputrc`** (not hardcoded, so it honours whatever cursor the operator
   picks in KDE). Cursor env vars do **not** leak into `systemd --user` (unlike
   QT_QPA_PLATFORMTHEME, ADR 0122 — VM-verified), so no compositor→KDE cursor
   leak to strip.

## Considered options

- **Per-session `XDG_CONFIG_HOME`** — the only true `kdeglobals` isolation, but
  splits all config between sessions; rejected as heavyweight (ADR 0104 stands).
- **Keep `kcolorscheme` off on combined boxes** (0104/0108) — rejected: it is the
  one gap breaking the cohesive Qt look under the compositor, and the reset makes
  it safe.
- **`kcolorscheme` in the committed `config.toml`** — rejected: a hand-stow
  without the installer's KDE reset would then leak Noctalia into Plasma; keep the
  leak-causing template in the seeded copy, shipped with its reset.
- **Hardcode the KDE cursor in the reset** — rejected: it would fight an operator
  who changes their KDE cursor; read `kcminputrc` instead.

## Consequences

- **Cohesive Noctalia look under niri/Hyprland** across GTK, plain-Qt **and**
  KColorScheme apps, for every palette — VM-verified with Dolphin.
- **KDE stays Breeze** on a combined box: `kdeglobals`, GTK and cursor all
  reasserted on Plasma login, on top of the ADR 0122 Qt platform-theme un-leak.
- **`config.toml` seeded copy carries `kcolorscheme` on every box class** — the
  committed source stays clean (one authored file); ADR 0108's per-box divergence
  is replaced by a uniform seeded injection.
- New fleet surface: unconditional preset injection, one `/usr/local/bin` helper
  + renamed autostart (combined-box-gated), and a gsettings cursor reassert line
  per compositor autostart. Guarded by `noctalia-stow.bats` + `kde-adapter.bats`.
- **`kde-gtk-breeze-reset.desktop` is renamed** to `kde-session-reset.desktop`
  (now GTK + colours + cursor); ADR 0116's file name is superseded here.
