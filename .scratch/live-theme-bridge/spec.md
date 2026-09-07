# Spec: Live Theme Bridge — repaint running apps on Noctalia theme change

Status: ready-for-agent

Anchored by **ADR 0116**. Extends the [[App Theming Bridge]] (ADR 0102/0104/
0108) and uses the [[Wayland Shell Companion]] and [[Package Resolver]] glossary
terms. Does **not** overturn ADR 0104 — Plasma isolation is kept by confinement.

## Problem Statement

I ship a themed desktop — the [[Wayland Shell Companion]] (Noctalia) paints the
shell and, via the [[App Theming Bridge]], makes GTK and Qt apps follow its
palette. But that following only lands on a **fresh app launch**. When I change
the Noctalia theme *while apps are open* — flip dark/light, or switch palette
(Catppuccin → Gruvbox, builtin or community) — every already-running window
stays on the old colors until I close and reopen it. It feels like "only
dark/light is respected, the theme is not," even though the color files on disk
have already updated. I want my open apps to repaint the moment I change the
theme, on my wl-roots compositors — **without** breaking how apps look when I log
into Plasma on a combined box.

## Solution

Ship the **Live Theme Bridge**: the runtime counterpart to the file-writing
[[App Theming Bridge]]. Noctalia already rewrites `qt6ct/colors/noctalia.conf`
and `gtk-{3,4}.0/noctalia.css` on **every** theme change (proven live on the
`arch-combined` VM: a `builtin Gruvbox` set flipped the qt6ct base
`#1e1e2e`→`#282828` and rewrote the GTK css) — so newly-launched apps already
follow any theme. The missing half is that running apps never re-read those
files. The bridge is a long-lived compositor-session process that watches the
generated color files and, on each change, nudges each toolkit to re-read and
repaint. It ships fleet-wide but is **isolated by confinement, not exclusion**:
it runs only from the compositor autostart and writes only compositor-private
state plus shared theme-name that `kde-gtk-config` already resets to Breeze on
every Plasma login — so a combined `kde`+compositor box gets live theming in its
compositor session with Plasma still deterministically Breeze, needing no
Plasma-side reset script and no per-host gate.

## User Stories

1. As an operator, I want my open Qt apps to repaint when I change the Noctalia
   palette, so that pcmanfm-qt and other Qt tools match the shell without a
   relaunch.
2. As an operator, I accept that open GTK apps pick up a new palette on next
   launch on native Wayland (a load-once `gtk.css` limitation), while XWayland
   GTK apps repaint live via the best-effort nudge, so that GTK follows as far as
   the toolkit allows without brittle restart hacks.
3. As an operator, I want a dark/light flip to repaint running apps live, so
   that toggling mode no longer forces me to reopen every window.
4. As an operator, I want a full palette switch (not just mode) to be respected,
   so that any theme — builtin or community — reaches my apps.
5. As an operator, I want live-follow to work whether I change the theme from
   the `custom-shortcut` cycle tile OR the Noctalia GUI, so that no trigger path
   is missed.
6. As an operator, I want live-follow to work identically on niri and Hyprland,
   so that switching compositor doesn't change how theming behaves.
7. As an operator on a combined `kde+niri+hyprland` box, I want live-follow in my
   compositor session, so that a combined box is not second-class to a pure one.
8. As an operator on a combined box, I want Plasma to stay Breeze Dark, so that I
   never enter KDE and see apps mis-themed by the compositor session.
9. As an operator, I do NOT want a separate Plasma-login reset script, so that we
   don't duplicate what `kde-gtk-config` already does natively.
10. As an operator, I do NOT want the bridge gated off combined hosts, so that
    confinement (not exclusion) is what protects Plasma.
11. As an operator, I accept that GTK4/libadwaita apps pick up palette colors on
    next launch (mode still follows live), so that we don't resort to brittle
    app-restart hacks for a shrinking class of apps.
12. As an operator on a pure-compositor box, I want KDE-framework apps
    (Dolphin/Gwenview/Kate) to keep repainting live via the existing
    `KGlobalSettings` notify, so that the `kcolorscheme` path (ADR 0108) is
    unaffected.
13. As an operator, I want the bridge to start with my compositor session, so
    that it is running before I touch the theme and dies when I log out.
14. As an operator on Hyprland, I want the bridge launched from the compositor
    autostart rather than a systemd-user unit, so that it actually starts under
    `start-hyprland` (ADR 0070).
15. As an operator on a fresh install, I want the bridge present with zero setup,
    so that a newly-provisioned box has live theming out of the box.
16. As an operator stowing this repo standalone (no installer), I want the bridge
    script and autostart lines to still be present, so that `stow .` themes apps
    the same way.
17. As an operator, I want the tool that watches the files (`inotify-tools`)
    installed automatically, so that the bridge has `inotifywait` available.
18. As an operator, I want the bridge to make no persistent write that Plasma
    reads and does not itself reset, so that nothing leaks across sessions.
19. As a maintainer, I want the drift/shape guards extended for the new payload,
    so that CI catches a dropped script, a missing autostart line, or an
    unresolved package.
20. As a maintainer, I want the new component recorded in the domain docs and an
    ADR, so that a future reader understands why we touch `qt6ct.conf`, toggle
    `gtk-theme`, and treat GTK4 as relaunch-only.

## Implementation Decisions

- **New component: the Live Theme Bridge** (ADR 0116) — a long-lived
  compositor-session process, delivered as the curated script
  `noctalia-theme-bridge`, the runtime counterpart to the file-writing
  [[App Theming Bridge]].
- **Trigger = inotify on the Noctalia-generated color files**
  (`qt6ct/colors/noctalia.conf`, `gtk-{3,4}.0/noctalia.css`), NOT a Noctalia
  subscription API. `noctalia msg` offers `templates-apply` / `color-scheme-set`
  to *cause* a render but nothing to *subscribe* to completion; watching the
  outputs catches every trigger path (cycle tile + GUI) with no dependency on an
  IPC that may not exist.
- **Per-toolkit repaint nudge** (mechanisms verified live on the VM):
  - **Qt6** → an **atomic rewrite** of `qt6ct.conf` (copy then rename in place).
    qt6ct watches its config *directory*, so a bare mtime `touch` does not fire
    it — a rename into the dir does; then `applySettings()` re-runs and running
    Qt apps repaint. **This is the working live path** (verified across three
    palettes + dark/light).
  - **GTK (3 and 4)** → **relaunch-only for palette on native Wayland.** The
    palette lives in the load-once user `gtk.css` (`@import noctalia.css`) that a
    running GTK app never re-reads, and `colorreload-gtk-module` is a KDE **X11**
    path inert under native Wayland (verified: a Wayland `nm-connection-editor`
    stayed on its launch-time palette through every change). A transient
    `gsettings` `gtk-theme` **read-toggle-restore** is kept **best-effort** — it
    repaints XWayland/X11 GTK apps and preserves Noctalia's own theme name.
    Dark/light still follows live for libadwaita via the portal.
  - **KColorScheme apps** (pure-compositor boxes, `kcolorscheme` on per ADR
    0108) → already repaint live via the `KGlobalSettings` D-Bus notify
    Noctalia's `kde-color-scheme` post-action emits; no bridge work.
- **Launched from the compositor autostart, not systemd-user.** A
  `spawn-at-startup` in niri's curated `autostart.kdl` and a `hyprland.start`
  exec in Hyprland's curated `autostart.lua`, beside the existing
  `noctalia --daemon` line. Rationale: Hyprland runs via `start-hyprland`,
  deliberately not the systemd/uwsm session (ADR 0070), so a user unit would
  reach niri but not Hyprland — the same reason `QT_QPA_PLATFORMTHEME` is set
  per-compositor (ADR 0102).
- **Ships fleet-wide; isolated by confinement, not a per-host gate.** The bridge
  writes only compositor-private `qt6ct.conf` and shared theme-name/dconf that
  `kde-gtk-config` reasserts to Breeze on every Plasma login, and runs only from
  the compositor autostart (never inside a Plasma session). So it is safe on a
  combined box — no `ENVIRONMENT_DESKTOP` gate, unlike the `kcolorscheme`
  injection (ADR 0108), and no Plasma-side reset script (that role is already
  `kde-gtk-config`).
- **Package.** `inotify-tools` (provides `inotifywait`) joins
  `noctalia_preset_packages` in the niri package map, shared by install and the
  [[Package Resolver]]. Traced to the Arch Wiki at implementation time per the
  repo's grounding rule.
- **Delivery mirrors ADR 0108.** The script is a stow-owned dotfile **and**
  seeded to `/etc/skel` by the shared Noctalia preset (the installer never
  stows, ADR 0095); the autostart lines land in the curated per-compositor
  configs (already seeded).
- **Combined-box KDE Breeze reset (ADR 0116, from VM testing).** Cross-session
  reboot testing showed `kde-gtk-config` does **not** auto-reset the shared GTK
  theme on Plasma login (correcting ADR 0104), so a compositor session's
  `adw-gtk3-dark`+`noctalia.css` accent leaks into KDE apps. The KDE adapter
  (`kde.sh`) seeds a **combined-box-gated, KDE-only** autostart
  (`kde-gtk-breeze-reset.desktop`, `OnlyShowIn=KDE`) that reasserts
  `gtk-theme=Breeze` on Plasma login; the compositor side reasserts
  `adw-gtk3-dark` via Noctalia — symmetric. Gated on `ENVIRONMENT_DESKTOP`
  carrying a compositor (pure KDE must not seed it — it would clobber the
  operator's own GTK theme).
- **Domain docs.** ADR 0116 written (with the VM-testing corrections); a **Live
  Theme Bridge** glossary entry added to `CONTEXT.md` beside the
  [[App Theming Bridge]]; ADR 0104 gets a correction note.

## Testing Decisions

Good tests assert **external, committed behavior** — the shape of the stow/seed
payload and the resolved package sets — not the bridge's runtime internals (this
repo has no live desktop under test; the reload nudges are verified by hand on
the VM at implementation time, not in CI). Reuse the **existing** seams; no new
seam is introduced.

- **Seam 1 — the curated stow-payload shape guard (`noctalia-stow.bats`).** The
  same file that already asserts `config.toml` required keys, the GTK
  `settings.ini` shape, `qt6ct.conf`, and per-compositor plumbing. Add
  assertions that:
  - `noctalia-theme-bridge` exists under the curated `.local/bin` payload and is
    executable.
  - niri's `autostart.kdl` and Hyprland's `autostart.lua` each spawn the bridge
    at compositor startup, beside `noctalia --daemon`.
  Prior art: this file's existing `grep`-the-committed-payload assertions for the
  Bibata cursor and the `QT_QPA_PLATFORMTHEME` per-compositor lines.
- **Seam 2 — the resolver package seam (the profiles/package resolver bats).**
  Assert `inotify-tools` resolves for **niri and hyprland** (and is part of the
  Noctalia preset base). Prior art: the adjacent `adw-gtk-theme` / preset-package
  and `bibata-cursor-git` "resolves under niri and hyprland" cases.

Both seams are existing and the highest point in their layer (committed-payload
shape vs. resolved package set); they can't be merged (different resolution
layers).

## Out of Scope

- **GTK4/libadwaita live palette repaint.** Load-once `gtk.css`; palette colors
  follow on next launch (mode still live). Explicitly not chased.
- **A Plasma-side Breeze reset script.** `kde-gtk-config` already does this on
  every Plasma login; duplicating it is rejected (ADR 0116).
- **A per-host `kde` gate for the bridge.** Confinement to the compositor
  autostart protects Plasma; gating is rejected.
- **Changing the palette / introducing wallpaper-driven color.** The default
  stays the fixed community palette (ADR 0101); this spec only makes running apps
  follow whatever theme is set.
- **GTK2 / Qt5.** No Noctalia template (App Theming Bridge scope, ADR 0102).
- **Migrating already-provisioned boxes.** Reaches fresh installs and freshly
  stowed configs; no migration tooling.
- **CI/runtime testing of the live reload.** Out of the repo's test model;
  coverage is committed-payload shape + resolver assertions, verified by hand on
  the VM.

## Further Notes

- The gap was confirmed empirically on the running `arch-combined` VM (niri
  session): `noctalia msg color-scheme-set builtin Gruvbox` rewrote both the
  qt6ct color file and the GTK `noctalia.css`, while the running apps did not
  repaint — establishing that file-following already works and only the runtime
  re-read is missing.
- The GTK isolation is governed by `gtk-theme-name` (adw-gtk3-dark vs Breeze),
  which each session already reasserts (Noctalia on compositor daemon-start,
  `kde-gtk-config` on Plasma login); Noctalia's `noctalia.css` and
  `kde-gtk-config`'s `colors.css` use largely disjoint variable namespaces
  (standard libadwaita names vs `*_breeze`), so their co-`@import` into one
  `gtk.css` does not itself fight.
- Qt is cleanly isolated per session by `QT_QPA_PLATFORMTHEME` (qt6ct under the
  compositor, plasma-integration under Plasma), so the Qt nudge cannot leak into
  Plasma.
- Confirm at implementation time on the VM: that `touch qt6ct.conf` repaints a
  running Qt app; the exact `gsettings gtk-theme` toggle that fires
  `colorreload` without a visible flash; and the Arch Wiki grounding for
  `inotify-tools`.
