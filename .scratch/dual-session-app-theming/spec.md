# Spec: Dual-session app theming isolation (KDE + Noctalia compositors)

Status: ready-for-agent

Anchored by **ADR 0104** (amends ADR 0102). Uses the [[App Theming Bridge]],
[[Wayland Shell Companion]], [[Desktop Environment Adapter]], and
[[Environment Runner]] glossary terms.

## Problem Statement

I ship themed desktops for three [[Desktop Environment Adapter]]s — KDE, niri,
and Hyprland — and the installer lets a single [[Host Profile]] select more than
one (`environment.desktop: [kde, niri]`, `[kde, hyprland]`, or all three). On
such a combined machine every adapter runs (the [[Environment Runner]] loops the
desktop set) and every session shares one `$HOME`. The [[App Theming Bridge]]
(ADR 0102) made the [[Wayland Shell Companion]] (Noctalia) own GTK/Qt app color
through config files that KDE **also** owns and that are neither per-session nor
namespaced. So on a combined box the two environments fight over the same bytes,
and the apps look wrong:

- After I use a compositor session, my **next KDE (Plasma) session comes up in
  Catppuccin instead of Breeze Dark** — Noctalia's `kcolorscheme` template
  merges its colors into the same `~/.config/kdeglobals` that Plasma reads.
- My **dotfiles repo is perpetually dirty** — Plasma's `kde-gtk-config` rewrites
  the GTK `settings.ini` at every login, and because those are stow symlinks
  into the repo, the write lands *in* the repo.
- A stale `xsettingsd.conf` ships in the payload naming a retired theme/cursor
  and is launched by nothing.

I want the look to be **identical between Qt and GTK apps on the compositors and
to follow the palette I set in Noctalia**, and I want **KDE to stay Breeze Dark
and never break**, even when both live on one machine.

## Solution

Keep the guest (Noctalia) from writing the host's (KDE's) identity files on a
shared machine, and stop Plasma from writing the version-controlled payload.
Three moves, from the user's perspective:

1. Noctalia no longer touches `kdeglobals`, so a KDE session always stays the
   Breeze Dark it was seeded as — deterministically, with no login scripts and
   no color flash.
2. The GTK `settings.ini` files are **seeded as real files**, not stowed
   symlinks, so Plasma can legitimately manage them on KDE at runtime while the
   dotfiles repo stays clean; the compositor keeps `adw-gtk3-dark` plus
   Noctalia's live `gtk.css` colors.
3. The dead `xsettingsd.conf` is removed.

Colors on the compositors always follow Noctalia (GTK via `gtk.css` loaded at
GTK's USER priority, Qt via the qt6ct palette). On a combined box, the only
bounded cost is that a KDE-native app *launched under a compositor* keeps
Noctalia's base palette but shows Breeze `KColorScheme` accent tints.

## User Stories

1. As an operator running only niri or only Hyprland, I want GTK and Qt apps to
   follow Noctalia's palette, so that my apps match my shell.
2. As an operator running only KDE, I want a fresh login to be Breeze Dark, so
   that the desktop looks finished out of the box.
3. As an operator on a `kde+niri` box, I want my KDE session to stay Breeze Dark
   even after I have used a niri session, so that switching sessions never
   repaints Plasma in the compositor's palette.
4. As an operator on a `kde+hyprland` box, I want the same guarantee, so that
   Plasma is unaffected by Hyprland's Noctalia theming.
5. As an operator running all three desktops on one machine, I want each session
   to render correctly for its own environment, so that no session pollutes
   another.
6. As an operator, I want Qt and GTK apps to look the same as each other on the
   compositors, so that the toolkit an app is built with is not visible as a
   color mismatch.
7. As an operator, I want the app look to be identical between niri and
   Hyprland, so that switching compositor does not change how my apps look.
8. As an operator, I want apps to follow a later palette change in Noctalia, so
   that cycling the palette re-themes apps without editing files.
9. As an operator, I do NOT want my dotfiles git working tree to show as
   modified after a KDE login, so that Plasma's routine GTK writes never dirty
   the repo I version-control.
10. As an operator, I want KDE to keep managing its own GTK theme (Breeze) at
    runtime, so that GTK apps under Plasma match the rest of the KDE session.
11. As an operator on a KDE-only machine, I want the installer to seed no GTK
    `settings.ini`, so that Plasma generates it itself and there is no stale
    default fighting Plasma.
12. As an operator on a compositor machine, I want the GTK `settings.ini` seeded
    with `adw-gtk3-dark`, so that GTK3 apps have the right base theme on a bare
    wlroots session with no settings daemon.
13. As an operator, I want the seeded GTK defaults to be host-neutral (no
    hard-coded DPI/scaling), so that a system default in `/etc/skel` is correct
    on any hardware.
14. As an operator, I want GTK4/libadwaita apps to keep following Noctalia's
    `gtk.css` (no forced GTK4 theme name and no `GTK_THEME`), so that modern GTK
    apps are not broken by a competing theme.
15. As an operator, I want a KDE-native app (Dolphin/Gwenview/Kate) opened under
    a compositor to still carry Noctalia's base palette, so that it is not a
    jarring default-colored window.
16. As an operator, I accept that such a KDE-native app under a compositor shows
    Breeze `KColorScheme` accent tints on a combined box, so that KDE's own
    session can stay pure Breeze — a trade I explicitly chose.
17. As an operator, I want the stale `xsettingsd.conf` removed from the payload,
    so that the repo carries no dead config naming a retired theme/cursor.
18. As an operator, I want `qt6ct.conf` to remain stowed and shared, so that Qt
    theming on the compositors is unchanged (Plasma ignores it, so it is safe).
19. As a maintainer, I want the drift guard updated to read the seeded GTK
    content from the preset rather than a repo file, so that CI catches a
    regression if the seed is dropped or malformed.
20. As a maintainer, I want a guard asserting the `kcolorscheme` template is
    absent from the shared Noctalia config, so that the kdeglobals leak cannot
    silently return.
21. As a maintainer, I want the decision and its rejected alternatives recorded
    in an ADR and the glossary, so that a future reader understands why Noctalia
    deliberately does less on KColorScheme and why GTK config is seeded.

## Implementation Decisions

- **Drop the `kcolorscheme` template fleet-wide** from the [[Wayland Shell
  Companion]]'s shared, stow-owned `config.toml` (`[theme.templates]
  builtin_ids`). This stops Noctalia both generating the standalone KDE
  `.colors` file and merging `[Colors:*]` into `~/.config/kdeglobals`. The
  template is removed unconditionally, not gated on the desktop set: its only
  consumers are `KColorScheme` widgets in KDE-framework apps, which exist only
  where the KDE adapter ran — exactly the combined box where the merge leaks. A
  pure compositor uses `pcmanfm-qt` (plain Qt, themed by the surviving `qt`
  template), so nothing there consumes it.
- **GTK `settings.ini` move from stowed to seeded.** The two files are removed
  from the stow payload and instead written as real files into `/etc/skel` by
  the shared Noctalia preset (the compositor-agnostic module sourced by both the
  niri and Hyprland adapters, ADR 0090/0097). Seeded content: `adw-gtk3-dark`
  plus icon (`Papirus-Dark`), font (`Noto Sans`) and `prefer-dark` in gtk-3.0;
  **no** theme name in gtk-4.0 so libadwaita follows `gtk.css`. Because the
  preset runs only when a compositor with `wayland_shell=noctalia` is present, a
  KDE-only host seeds nothing and Plasma generates the files at first login.
- **Seeded defaults are host-neutral.** The previous stowed `settings.ini`
  carried a host-bound `gtk-xft-dpi`; the `/etc/skel` seed drops it (a system
  default must not pin one machine's DPI).
- **`qt6ct.conf` stays stowed and shared**, pointing at Noctalia's generated
  `noctalia` scheme with `custom_palette=true`. Plasma uses its own
  `plasma-integration` platform theme and never reads `qt6ct.conf`, so it is
  compositor-private and safe to share unchanged.
- **`QT_QPA_PLATFORMTHEME=qt6ct` per-compositor** is unchanged (niri
  `environment {}`, Hyprland `env =`), as is the KDE adapter's `/etc/skel`
  Breeze Dark seed (ADR 0088).
- **Delete `xsettingsd.conf`** from the payload.
- **Rejected alternatives** (recorded in ADR 0104): reassert-Breeze-on-KDE-login
  (churn, permanent kdeglobals tug-of-war); a per-session `GTK_THEME` override
  (libadwaita branches on it and gets force-themed onto `adw-gtk3-dark`, which
  breaks GTK4); `chmod -w` the stowed file (blocks Plasma's own Breeze write,
  contradicting story 10); per-session `XDG_CONFIG_HOME` (documented-but-
  unshipped folklore, too heavy).

## Testing Decisions

- **What makes a good test here:** assert external, committed behavior — the
  shape of the payload and the preset's seed — not implementation internals. The
  tests read committed artifacts statically (no chroot, no pacman, no running
  session), which is the highest, cheapest seam and matches the existing drift
  guards.
- **Single seam, existing:** `.installer/tests/config/noctalia-stow.bats` — the
  same drift-guard suite that already asserts the [[App Theming Bridge]] payload
  (ADR 0102). No new seam is introduced. It is extended to:
  - assert the GTK `settings.ini` repo files are **absent** and that the shared
    preset seeds both (story 19);
  - assert the seeded gtk-3.0 carries `adw-gtk3-dark` + icon/font/prefer-dark,
    drops the stale breeze cursor and the host DPI (stories 12–13);
  - assert the seeded gtk-4.0 carries no theme name (story 14);
  - assert `config.toml` no longer lists `kcolorscheme` (story 20);
  - keep the existing `qt6ct.conf` and package guards (story 18).
- **Prior art:** the pre-existing App Theming Bridge tests in the same file
  (ADR 0102), and the config.toml drift guard that mirrors the enabled plugin
  set against the installer's core set. The niri/Hyprland adapter suites and the
  configs-conflict-detector remain green as regression coverage.

## Out of Scope

- Changing how KDE itself themes GTK (it keeps `breeze-gtk` + `kde-gtk-config`
  at runtime, ADR 0088).
- Full-fidelity `KColorScheme` theming of KDE-native apps *under a compositor*
  on a combined box — deliberately traded away for a deterministic KDE session.
- GTK2 and Qt5 (never in the bridge's scope, ADR 0102).
- The gtk-4.0/gtk.css contention between Plasma and Noctalia beyond "never stow
  gtk.css" (both regenerate it at their own login; it was never stowed).
- X11/XWayland GTK-app parity via an XSettings daemon (xsettingsd is removed,
  not re-launched; re-add correctly later if that parity is ever wanted).

## Further Notes

- Colors always follow Noctalia on the compositors regardless of the base GTK
  theme name, because the user `gtk.css` loads above any theme; the compositor's
  GTK3 base *widget style* may briefly be Breeze after a Plasma login until
  Noctalia re-applies (gsettings + `gtk.css`) at the next compositor login —
  Noctalia re-applies its full theme on every daemon start.
- This spec was implemented alongside ADR 0104 and the `CONTEXT.md` glossary
  update in the same change.
