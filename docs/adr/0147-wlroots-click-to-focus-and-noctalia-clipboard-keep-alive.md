# ADR 0147: wlroots click-to-focus + Noctalia clipboard keep-alive

## Status
Accepted, 2026-09-28. Verified in the VM (`.scratch/wlroots-clipboard-focus/`).
Still open: keeping the clipboard after close on Hyprland once 0.57 ships.
Applies to both wlroots compositors (niri, Hyprland) of the
[[Wayland Shell Companion]]. Extends ADR 0100 (Noctalia owns the QoL layer).

## Context
There are two bugs on the wlroots sessions:

- **Menus lose focus.** On Hyprland, `follow_mouse = 1` moves keyboard focus
  to whatever window is under the pointer. In the VM, VSCodium's menu closed
  when the pointer crossed kwrite on its way to an item. Qt menus survived.
  niri has no `focus-follows-mouse`, so the two compositors behave
  differently. Hyprland's "not responding" dialog (`hyprland-dialog`) also
  takes focus whenever a slow Electron app misses pings.
- **Copy/paste between Chromium/Electron apps and Qt/GTK apps.** In the VM,
  every app runs native Wayland on both compositors (no XWayland path), and
  live copy/paste works in every direction. What fails:
  - When the source app closes, its clipboard contents disappear. Noctalia
    (the one clipboard client on both sessions) takes them over only after
    the compositor sends data-control clients a "selection is now empty"
    (`selection(null)`) event. niri sends it, and the takeover works there.
    Hyprland 0.56.2 doesn't (`CSeatManager::setCurrentSelection(nullptr)`
    only notifies `wl_data_device`). The fix, hyprwm/Hyprland#16117, is
    merged but not in a release yet.
  - GTK middle-click paste is off: `gsettings-desktop-schemas` 50 defaults
    `gtk-enable-primary-paste` to false (GNOME's upstream change).

## Decision
- **Click-to-focus on both compositors.** Hyprland switches to
  `follow_mouse = 2`: keyboard focus stays where it is until you click, but
  scrolling still reaches the window under the pointer. It also sets
  `float_switch_override_focus = 0`: the default (1) still moves focus when
  the pointer crosses between a floating and a tiled window, which closed a
  dialog's context menu in the VM. niri keeps its default. Tested live in the
  VM (Hyprland): menus and submenus in kwrite, VSCodium, Chromium and GTK
  (zenity) stay open across another window, and the chosen item runs.
- **Hyprland's not-responding dialog stays enabled, with more slack.**
  `misc:anr_missed_pings = 15` (3× the default 5; the wiki allows 1–20), so
  apps that are only slow to start don't steal focus, while really hung apps
  still get the dialog.
- **Hyprland's update-news and donation popups are off.**
  `ecosystem.no_update_news` / `no_donation_nag = true`: in the VM the
  "updated to 0.56.2" popup took focus after a config reload. Release notes
  stay on GitHub.
- **Noctalia keeps the clipboard alive.** Set
  `[shell] clipboard_keep_from_closed_apps = true` explicitly in the curated
  `config.toml` (already upstream's default; setting it pins it). No new
  package, on either compositor.
- **On Hyprland, keeping the clipboard after close waits for upstream.** No
  stopgap tool. Until a release with #16117 (expected 0.57) is installed,
  Hyprland loses the clipboard when its source app closes. The VM prober
  records that as expected (`keep=xfail`) while Hyprland < 0.57, and as a
  failure after that.
- **GTK middle-click paste back on.** Both compositors' autostart sets
  `org.gnome.desktop.interface gtk-enable-primary-paste true`, next to the
  existing gsettings cursor lines.
- **Coverage:** the regular clipboard works in both directions and survives
  the source app closing (on Hyprland: from 0.57). Primary works in both
  directions while the source app is open; it is not kept alive after close.
- **No Chromium/Electron Wayland flags, no `xwayland-satellite`.** The repro
  found no XWayland path.

## Considered Options
- **Keep focus-follows-mouse and only fix popups** (Hyprland rules for
  menus). Rejected: it treats each popup case separately, and the two
  compositors would still behave differently.
- **`wl-clip-persist --clipboard regular`**, even as a Hyprland-only
  stopgap. Rejected: 1 contributor, no push since 2025-09, a niri crash
  report (niri #2250), a second clipboard owner next to Noctalia, and the
  real bug is already fixed upstream.
- **CopyQ** (active, in `extra`). Rejected: a full history manager that
  duplicates Noctalia's clipboard panel, and keeping the clipboard after
  close is unproven.
- **clipman** (chmouel fork). Rejected: AUR only, text only, and the
  Hyprland wiki warns it breaks rich content.
- **Turn `cliphist` on by default.** Rejected: it only records history. It
  does not keep the clipboard alive after the source app closes.
- **Disable the not-responding dialog.** Rejected: really hung apps would
  give no signal.
- **Persist the primary selection too.** Rejected: upstream tools and the
  Hyprland wiki warn it breaks text selection in some apps.

## Consequences
- Keeping the clipboard alive depends on Noctalia plus a compositor that
  sends `selection(null)`. Noctalia #3793 was fixed before 5.0.0 and was not
  seen in the VM.
- Noctalia doesn't take over clipboard contents set by a data-control
  client (`wl-copy`), and Hyprland 0.56 drops primary set by `wl-copy -p`.
  So the prober uses kitty (a real client) as the clipboard owner.
- With `wayland_shell = none` the sessions have no clipboard keep-alive; the
  operator's own dotfiles own that choice.
- Chromium ships on hosts through core's `mermaid-cli`, which depends on it.
  The fix is not specific to Chromium.
