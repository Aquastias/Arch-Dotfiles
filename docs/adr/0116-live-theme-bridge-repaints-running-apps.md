# Live Theme Bridge repaints running apps on wl-roots sessions

---
Status: accepted. **Extends ADR 0102/0104/0108** (the App Theming Bridge). Those
made the *files* follow any Noctalia palette; this makes *already-running* apps
repaint without a relaunch. Does **not** overturn ADR 0104 — Plasma isolation is
kept by confinement, not by excluding combined hosts. Facts traced live in the
running `arch-combined` VM (niri session): a `builtin Gruvbox` set flipped the
qt6ct base `#1e1e2e`→`#282828` and rewrote `gtk-{3,4}.0/noctalia.css`, proving
file-following already works for any theme.

**Verified end-to-end on the VM with screenshots + pixel sampling.** Two
mechanism corrections came out of that testing and are folded in below: (a) the
Qt nudge is an **atomic rewrite** of `qt6ct.conf`, not a bare `touch` — qt6ct
watches its config *directory*, and a mtime `touch` does not fire a directory
watcher; the rewrite made pcmanfm-qt repaint live across Catppuccin→Gruvbox→Nord
and dark→light. (b) **GTK palette is relaunch-only on native Wayland** (not just
GTK4): a running Wayland GTK app never re-reads the load-once user `gtk.css`, and
`colorreload-gtk-module` is a KDE **X11** path inert under native Wayland. The
GTK nudge is kept **best-effort** (it does fire for XWayland/X11 GTK apps).
---

The App Theming Bridge (ADR 0102) writes Noctalia's palette into
`qt6ct/colors/noctalia.conf` + `gtk-{3,4}.0/noctalia.css` on **every** palette
change (builtin or community) — so a **newly-launched** Qt/GTK app already
follows any theme. The gap is that **running** apps do not re-read those files:
changing the Noctalia theme mid-session leaves every open window on the old
colors until it is closed and reopened. The operator reads this as "only
dark/light follows, the theme does not" — but the files *do* follow; the
toolkits just never reload them. This is a live-repaint gap, not a
file-following bug.

Why nothing repaints today, per toolkit:

- **Qt6/qt6ct** watches its config **directory**; Noctalia rewrites the
  `colors/` **subfile**, which does not reliably fire that watcher.
- **GTK (3 and 4)** loads `~/.config/gtk-{3,4}.0/gtk.css` (and its
  `@import noctalia.css`) **once at startup** with no runtime user-CSS reload.
  `kde-gtk-config`'s `colorreload-gtk-module` *would* poke a reload, but it is a
  KDE **X11** mechanism inert under native Wayland — so a running Wayland GTK app
  never picks up the new palette (VM-verified).

## Decision

Ship a **Live Theme Bridge**: a long-lived, compositor-session process
(`~/.local/bin/noctalia-theme-bridge`) that `inotifywait`s the Noctalia-written
color files and, on each write, nudges each toolkit to re-read — the runtime
counterpart to ADR 0102's file-writing bridge.

1. **Trigger = inotify on the generated files**, not a Noctalia subscription.
   `noctalia msg` exposes `templates-apply`/`color-scheme-set` (to *cause* a
   render) but nothing to *subscribe* to completion, so watching the outputs
   catches every trigger path — the `noctalia-cycle-palette` tile **and** the
   Noctalia GUI — with no dependency on an IPC that may not exist.

2. **Per-toolkit repaint nudge:**
   - **Qt6** → an **atomic rewrite** of `~/.config/qt6ct/qt6ct.conf` (copy then
     rename in place). qt6ct watches its config *directory*, so a bare mtime
     `touch` does **not** fire it — a rename into the dir does; then
     `applySettings()` re-runs and running Qt apps repaint. **This is the live
     path that works** (VM-verified across three palettes + dark/light).
   - **GTK (3 and 4)** → **relaunch-only for palette** on native Wayland. The
     palette lives in the load-once user `gtk.css` (`@import noctalia.css`) that
     a running GTK app never re-reads, and `colorreload-gtk-module` is a KDE
     **X11** mechanism inert under native Wayland (VM-verified: a Wayland
     nm-connection-editor stayed on its launch-time palette through every
     change). A transient `gsettings` `gtk-theme` read-toggle-restore is kept as
     a **best-effort** nudge — it *does* repaint XWayland/X11 GTK apps and is
     harmless otherwise; it reads and restores Noctalia's own theme name so it
     never overrides the mode Noctalia set. Dark/light still follows live for
     libadwaita apps via the portal.
   - **KColorScheme apps** (pure-compositor boxes, where `kcolorscheme` is on,
     ADR 0108) already repaint live via the `KGlobalSettings` D-Bus notify
     Noctalia's `kde-color-scheme` post-action emits — no bridge work.

3. **Launched from the compositor autostart**, not systemd-user: a
   `spawn-at-startup` in niri's `conf.d/autostart.kdl` and a `hyprland.start`
   exec in hypr's `conf.d/autostart.lua`, beside `noctalia --daemon`. Hyprland
   runs via `start-hyprland`, deliberately **not** the systemd/uwsm session (ADR
   0070), so a user unit would reach niri but not Hyprland — the same reason
   `QT_QPA_PLATFORMTHEME` is set per-compositor (ADR 0102).

4. **Fleet-wide, isolated by confinement — not excluded from combined boxes.**
   The bridge writes only compositor-private state (`qt6ct.conf`) and shared
   theme-name/dconf. It is launched *only* from the compositor autostart, so it
   never runs inside a Plasma session (VM-verified: no bridge process under
   Plasma). `kdeglobals` stays Breeze and KDE-native apps (Dolphin) render
   perfect Breeze on a combined box.

5. **Combined boxes need a KDE-side GTK Breeze reset** — the compositor session
   leaves the shared `gsettings` `gtk-theme` at `adw-gtk3-dark` + a
   `noctalia.css` accent, and **`kde-gtk-config` does NOT auto-reset it on Plasma
   login** (VM-verified — this **disproves ADR 0104's assumption**, and my first
   pass which relied on it). Without a reset, GTK apps under Plasma inherit
   Noctalia's accent (e.g. Gruvbox green in an otherwise-Breeze session). The KDE
   adapter (`kde.sh`) therefore seeds a **KDE-only autostart**
   (`~/.config/autostart/kde-gtk-breeze-reset.desktop`, `OnlyShowIn=KDE`) that
   sets `gtk-theme=Breeze` + `color-scheme=prefer-dark` on Plasma login. Seeded
   **only on a combined box** (`ENVIRONMENT_DESKTOP` has `niri`/`hyprland`) — on
   pure KDE it would clobber the operator's own GTK theme. `gsettings` is inlined
   in the `Exec` (the systemd XDG-autostart generator mangles a `$HOME` script
   path). This is the operator's original Q2 instinct, now proven necessary and
   symmetric: the compositor side reasserts `adw-gtk3-dark` via Noctalia on the
   next niri/Hyprland login. VM-verified across niri→KDE→hyprland reboots: every
   app is Breeze under Plasma, Noctalia-themed under the compositors, no leak.

6. **Delivery mirrors ADR 0108.** The bridge script is a stow-owned dotfile
   **and** seeded to `/etc/skel` by `noctalia-preset.sh` (the installer never
   stows, ADR 0095); `inotify-tools` (for `inotifywait`) joins
   `noctalia_preset_packages`; the autostart lines join the curated
   per-compositor configs. The KDE Breeze reset is seeded by `kde.sh` via
   `_seed_write` (the existing KDE-autostart-seed pattern, beside
   `plasma-welcome.desktop`), combined-box-gated.

## Considered options

- **Rely on `kde-gtk-config` to auto-reset GTK to Breeze on Plasma login** (my
  first pass, on ADR 0104's assumption) — **rejected after VM testing disproved
  it**: `kde-gtk-config` did **not** reset `gtk-theme`/`gtk.css` on login here, so
  GTK apps under Plasma showed Noctalia's accent. The **explicit KDE-side Breeze
  reset** (Decision 5, the operator's original Q2 instinct) is the accepted fix.
- **Seed the KDE reset on every KDE box** (not just combined) — rejected: on a
  pure-KDE box it would override the operator's own GTK theme every login; gate
  it on `ENVIRONMENT_DESKTOP` carrying a compositor.
- **Gate install on `ENVIRONMENT_DESKTOP` not containing `kde`** (like
  `kcolorscheme`, ADR 0108) — rejected: with the bridge confined to the
  compositor autostart and Plasma self-healing, gating only denies live-repaint
  to a combined box's compositor session for zero isolation benefit.
- **Wrap `noctalia-cycle-palette` to nudge apps** instead of a watcher —
  rejected: misses GUI-initiated palette changes, which never pass through that
  script.
- **A systemd-user service** for supervision — rejected on the `start-hyprland`
  fact above (ADR 0070); it would not reliably reach Hyprland.
- **Chase GTK live palette on Wayland** (restart apps, or ship a
  `noctalia.css`-watching GTK module) — rejected as brittle / disproportionate;
  the load-once `gtk.css` + X11-only `colorreload` ceiling is a native-Wayland
  fact, and mode still follows live. Left as a future option if GTK live palette
  ever becomes a hard requirement.

## Consequences

- **Changing the Noctalia theme mid-session repaints running Qt6 (and pure-box
  KDE) apps live**, on niri and Hyprland, on any box class — VM-verified across
  three palettes and dark/light.
- **GTK apps (3 and 4)** follow dark/light live (libadwaita) but pick up
  **palette colors on next launch** on native Wayland — the bounded, documented
  cost. The best-effort `gtk-theme` nudge still repaints XWayland/X11 GTK apps.
- **Plasma stays deterministically Breeze** on combined boxes: `kdeglobals` and
  KDE-native apps by confinement, and GTK apps by the KDE-side reset (Decision
  5). VM-verified across niri→KDE→hyprland reboots — no cross-session leak.
- New fleet surface: one autostart line per compositor, one seeded/stowed bridge
  script, `inotify-tools` in the preset (guarded by `noctalia-stow.bats` +
  resolver), and one combined-box-gated KDE autostart seed in `kde.sh` (guarded
  by `kde-adapter.bats`).
- **Correction to ADR 0104:** its claim that `kde-gtk-config` "rewrites [the GTK
  `settings.ini`] at every Plasma login" is not what happens on the current
  fleet — GTK theme state persists across sessions and must be reset explicitly
  (Decision 5). The rest of ADR 0104 (drop `kcolorscheme` on combined boxes;
  `kdeglobals` stays Plasma-owned) stands and is confirmed.
