# Live Theme Bridge repaints running apps on wl-roots sessions

---
Status: accepted. **Extends ADR 0102/0104/0108** (the App Theming Bridge). Those
made the *files* follow any Noctalia palette; this makes *already-running* apps
repaint without a relaunch. Does **not** overturn ADR 0104 — Plasma isolation is
kept by confinement, not by excluding combined hosts. Facts traced live in the
running `arch-combined` VM (niri session): a `builtin Gruvbox` set flipped the
qt6ct base `#1e1e2e`→`#282828` and rewrote `gtk-{3,4}.0/noctalia.css`, proving
file-following already works for any theme.
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
- **GTK3** would reload via `kde-gtk-config`'s `colorreload-gtk-module` (loaded
  through `gtk-modules`), but that module fires on a **theme-name or
  `colors.css`** change — a palette change keeps the name `adw-gtk3-dark` and
  only rewrites `noctalia.css`, so it never triggers.
- **GTK4/libadwaita** loads `~/.config/gtk-4.0/gtk.css` (and its
  `@import noctalia.css`) **once at startup** with no runtime user-CSS reload.

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
   - **Qt6** → `touch ~/.config/qt6ct/qt6ct.conf` (a top-level file the qt6ct
     dir-watcher *does* see) → `applySettings()` re-runs → live repaint.
   - **GTK3** → a transient `gsettings` `gtk-theme` toggle to force
     `colorreload-gtk-module` to fire → running GTK3 apps re-read `gtk.css`.
   - **GTK4** → **relaunch-only** (accepted ceiling). Mode (dark/light) still
     follows live via libadwaita's own portal subscription; palette colors land
     on next launch. The alternative — killing/restarting GTK4 apps to force a
     reload — is brittle and app-hostile for a shrinking class of apps.
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
   theme-name/dconf that `kde-gtk-config` **already reasserts to Breeze on every
   Plasma login**. It is launched *only* from the compositor autostart, so it
   never runs inside a Plasma session. A combined `kde+niri+hyprland` box
   therefore gets live theming in its compositor session with Plasma still
   deterministically Breeze — the ADR 0104 goal, reached without a per-host gate
   or a Plasma-side reset script (`kde-gtk-config` is that script).

5. **Delivery mirrors ADR 0108.** The script is a stow-owned dotfile **and**
   seeded to `/etc/skel` by `noctalia-preset.sh` (the installer never stows, ADR
   0095); `inotify-tools` (for `inotifywait`) joins `noctalia_preset_packages`;
   the autostart lines join the curated per-compositor configs.

## Considered options

- **An explicit Plasma-login Breeze reset** (the operator's first instinct, and
  ADR 0104's rejected "reassert Breeze on every KDE login") — rejected:
  `kde-gtk-config` is installed and already does exactly that (rewrites
  `settings.ini` to Breeze, regenerates `colors.css`, reloads via its module) on
  every Plasma login. Building our own duplicates KDE's own machinery for no
  gain.
- **Gate install on `ENVIRONMENT_DESKTOP` not containing `kde`** (like
  `kcolorscheme`, ADR 0108) — rejected: with the bridge confined to the
  compositor autostart and Plasma self-healing, gating only denies live-repaint
  to a combined box's compositor session for zero isolation benefit.
- **Wrap `noctalia-cycle-palette` to nudge apps** instead of a watcher —
  rejected: misses GUI-initiated palette changes, which never pass through that
  script.
- **A systemd-user service** for supervision — rejected on the `start-hyprland`
  fact above (ADR 0070); it would not reliably reach Hyprland.
- **Chase GTK4 live palette** (restart apps, or an injected reload no toolkit
  supports) — rejected as brittle; the load-once `gtk.css` ceiling is a GTK4
  design fact, and mode still follows live.

## Consequences

- **Changing the Noctalia theme mid-session repaints running Qt6, GTK3 and
  (pure-box) KDE apps live**, on niri and Hyprland, on any box class — the
  stated goal.
- **GTK4/libadwaita apps** follow dark/light live but pick up **palette colors
  on next launch** — the one bounded, documented cost.
- **Plasma stays deterministically Breeze** on combined boxes with no new
  Plasma-side component; isolation is by confinement, extending ADR 0104 rather
  than reversing it.
- New fleet surface: one autostart line per compositor, one seeded/stowed
  script, and `inotify-tools` in the preset — covered by the same
  `noctalia-stow.bats` + resolver seams that guard the App Theming Bridge.
