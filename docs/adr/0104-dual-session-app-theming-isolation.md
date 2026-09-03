# Dual-session app theming isolation (KDE + Noctalia compositors)

---
Status: accepted. **Amends ADR 0102** (App Theming Bridge) for hosts whose
`environment.desktop` set pairs `kde` with a wlroots compositor. Extends ADR
0088 (KDE seeds `/etc/skel`) and ADR 0090/0097 (shared Noctalia preset).
---

A multi-desktop host (`kde+niri`, `kde+hyprland`, or all three) runs **every**
adapter — `chroot/extras.sh` loops the resolved desktop set — and every session
shares **one `$HOME`**. ADR 0102 wired Noctalia to own GTK/Qt app color through
config files that KDE also owns and that are neither per-session nor namespaced,
so on a combined box the two environments fight over the same bytes:

- **`~/.config/kdeglobals`** — Noctalia's `kcolorscheme` template merges its
  `[Colors:*]` groups straight into `kdeglobals` (a native `kde-color-scheme`
  post-action, plus a `KGlobalSettings` D-Bus notify). Plasma reads that *same*
  file, so a compositor login repaints the **next Plasma session** Catppuccin
  instead of Breeze Dark. One file cannot hold two color schemes.
- **`~/.config/gtk-{3,4}.0/settings.ini`** — `kde-gtk-config`'s KDED module
  rewrites both at **every** Plasma login (unprompted). Stowed, they are
  symlinks into the dotfiles repo, so Plasma's write lands *in the repo*
  (perpetual `git` dirt via `QSaveFile`'s symlink-resolve) and flips the theme
  name to Breeze.
- **`~/.config/xsettingsd/xsettingsd.conf`** — stale (still names `Breeze` +
  `breeze_cursors`, both retired by ADR 0102/0098) and launched by nothing.

## Decision

Keep the guest (Noctalia) from scribbling in the host's (KDE's) identity files
on a shared machine. Three moves:

1. **Drop `kcolorscheme` from Noctalia's `builtin_ids`** (the shared, stow'd
   `config.toml`) — fleet-wide, not conditionally. It only feeds `KColorScheme`
   widgets in KDE-framework apps (Dolphin/Gwenview/Kate), which exist **only**
   when the KDE adapter ran — i.e. exactly the combined box where the merge
   leaks. On a pure compositor the file manager is `pcmanfm-qt` (plain Qt,
   themed by the surviving **`qt`** template), so nothing consumes it there. GTK
   and plain-Qt apps never read `kdeglobals`; a KDE-native app under a
   compositor still gets Noctalia's base palette via qt6ct, losing only
   `KColorScheme` accent tints, and only on a combined box.

2. **GTK `settings.ini` become seeded, never stowed.** The shared preset
   (`lib/chroot/noctalia-preset.sh`) writes real `/etc/skel` files —
   `adw-gtk3-dark` in gtk-3.0, **no** theme name in gtk-4.0 (libadwaita follows
   `gtk.css`, ADR 0102). Plasma legitimately owns these at runtime on KDE (the
   Q2 choice); the compositor keeps `adw-gtk3-dark` + Noctalia's live
   `gtk.css` colors. A KDE-only host seeds nothing — Plasma generates them on
   first login. As a `/etc/skel` system default they are host-neutral: the
   host-bound `gtk-xft-dpi` line is dropped.

3. **Delete `xsettingsd.conf`** — dead payload carrying retired values.

`qt6ct.conf` stays stowed unchanged: Plasma uses its own `plasma-integration`
platform theme and never reads `qt6ct.conf`, so it is compositor-private and
safe to share.

## Considered options

- **Reassert Breeze on every KDE login** (keep `kcolorscheme`, add a Plasma
  autostart re-applying BreezeDark; rely on Noctalia re-merging each compositor
  login). Now technically viable — Noctalia *does* re-apply its full theme on
  every daemon start — but rejected: it fights the OS at every login for accent
  colors in KDE-native apps rarely opened under a compositor, and leaves
  `kdeglobals` in a permanent tug-of-war.
- **`GTK_THEME` per-session env override** (force `adw-gtk3-dark` only in the
  compositor session). Rejected: libadwaita *branches* on `GTK_THEME` and gets
  force-themed onto `adw-gtk3-dark`, which adw-gtk3 upstream says breaks GTK4.
  Too blunt — it cannot be scoped to GTK3.
- **`chmod -w` the stowed `settings.ini`** (Arch Wiki's clobber fix). Rejected:
  `kde-gtk-config` then skips it, so Plasma can no longer set Breeze on KDE —
  contradicting the requirement that KDE stay Plasma-managed Breeze.
- **Per-session `XDG_CONFIG_HOME`.** The only mechanism that truly isolates
  `kdeglobals`, but a prior-art survey found it documented-yet-unshipped
  folklore; too heavy for the payoff.

The prior-art survey (Noctalia issues, end-4/dots-hyprland, niri/Hyprland
"fake-KDE-session" configs, Arch/GNOME/KDE docs) found **no project cleanly
solves the `kdeglobals` cross-session leak**: the field either accepts one
shared `kdeglobals` (the open leak) or *sidesteps* it with a compositor-private
Qt palette (qtengine, per-app `dolphinrc`, plain qt6ct). Dropping `kcolorscheme`
puts us in the clean camp — the surviving `qt` template already points qt6ct at
a private `noctalia.conf`, not a `KColorScheme` `.colors` file.

## Consequences

- **KDE never breaks:** the Plasma session stays Breeze Dark, deterministic, no
  login hooks, no flashes.
- **Compositor apps always follow Noctalia's *colors*** — `gtk.css` loads at
  `PRIORITY_USER` (above any base theme) and the qt6ct palette drives Qt —
  regardless of what Plasma last wrote to a shared file.
- **The dotfiles repo is no longer dirtied** by Plasma; the Plasma-written GTK
  files are ordinary `$HOME` files.
- **The narrow, bounded cost:** on a combined box, a KDE-native app launched
  *under a compositor* shows Noctalia's base palette with Breeze `KColorScheme`
  accents; and its GTK3 base widget *style* may be Breeze immediately after a
  Plasma login until Noctalia re-applies (gsettings + `gtk.css`) at the next
  compositor login. Colors — the stated goal — are unaffected either way.
- Pure `niri`/`hyprland` boxes are unchanged in every visible way (they had no
  `KColorScheme` consumers to lose).
