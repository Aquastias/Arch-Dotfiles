# 03 — Combined-box KDE GTK Breeze reset

**What to build:** on a combined `kde`+compositor box, GTK apps under Plasma must
render **Breeze**, not the accent a Noctalia (niri/Hyprland) session left in the
shared `$HOME`. VM testing (ADR 0116) found `kde-gtk-config` does **not**
auto-reset the shared `gsettings` `gtk-theme` on Plasma login (disproving ADR
0104), so a compositor session's `adw-gtk3-dark` + `noctalia.css` accent leaks
into KDE (e.g. a Gruvbox-green highlight in an otherwise-Breeze session). The KDE
adapter seeds a KDE-only autostart that reasserts Breeze on Plasma login; the
compositor side already reasserts `adw-gtk3-dark` via Noctalia, so the two
sessions stay symmetric with no leak.

**Blocked by:** None — independent of the bridge (this is the KDE side); pairs
with 01/02 for the full combined-box story.

**Status:** ready-for-agent

- [ ] `kde.sh` seeds `/etc/skel/.config/autostart/kde-gtk-breeze-reset.desktop`
      (via `_seed_write`, beside `plasma-welcome.desktop`) that runs
      `gsettings set …interface gtk-theme Breeze` + `color-scheme prefer-dark`,
      `OnlyShowIn=KDE`, gsettings **inlined** in `Exec` (the systemd
      XDG-autostart generator mangles a `$HOME` script path).
- [ ] Seeded **only on a combined box** (`ENVIRONMENT_DESKTOP` carries `niri` or
      `hyprland`); a **pure-KDE** box does NOT seed it (it would clobber the
      operator's own GTK theme every login).
- [ ] `kde-adapter.bats` asserts both: combined box seeds the reset (Breeze +
      `OnlyShowIn=KDE`); pure KDE does not.
- [ ] Verified on the VM: niri(theme)→KDE shows all apps Breeze (Dolphin + GTK +
      Qt), kdeglobals Breeze, bridge not running; KDE→niri re-themes correctly.
