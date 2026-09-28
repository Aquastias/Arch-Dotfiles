# ADR 0147: wlroots click-to-focus + Noctalia clipboard keep-alive

## Status
Proposed. Not implemented yet; the VM repro for
`.scratch/wlroots-clipboard-focus/` has not run. Applies to both wlroots
compositors (niri, Hyprland) of the [[Wayland Shell Companion]]. Extends ADR
0100 (Noctalia owns the QoL layer).

## Context
There are two bugs on the wlroots sessions:

- **Menus lose focus.** On Hyprland, `follow_mouse = 1` moves keyboard focus
  to whatever window is under the cursor. When the cursor passes over another
  surface on its way to a menu (e.g. the File menu), focus can move with it,
  and the menu closes before you can pick an item. niri has no
  `focus-follows-mouse`, so the two compositors behave differently.
- **Copy/paste fails between Chromium/Electron apps (Chromium, VSCodium) and
  Qt/GTK apps**, in both directions. On Wayland the app you copied from owns
  the clipboard contents, so they disappear when that app closes. Noctalia
  (the shell on both sessions) is already the one clipboard client, through
  its history feature.

## Decision
- **Click-to-focus on both compositors.** Hyprland switches to
  `follow_mouse = 2`: keyboard focus stays where it is until you click, but
  scrolling still reaches the window under the cursor. niri keeps its default.
  Both compositors now behave the same.
- **Noctalia keeps the clipboard alive.** Set
  `[shell] clipboard_keep_from_closed_apps = true` explicitly in the curated
  `config.toml` (it is already upstream's default; setting it pins it). When
  the source app closes, Noctalia takes over the regular clipboard contents.
  No new package.
- **Coverage:** the regular clipboard works in both directions and survives
  the source app closing. The primary selection (middle-click paste) works in
  both directions while the source app is open; it is not kept alive after
  the source closes.
- **Chromium/Electron flags and `xwayland-satellite`** are added only if the
  VM repro shows an XWayland path is the cause.

## Considered Options
- **Keep focus-follows-mouse and only fix popups** (Hyprland rules for
  menus). Rejected: it treats each popup case separately, and the two
  compositors would still behave differently.
- **`wl-clip-persist --clipboard regular`.** Rejected: 1 contributor, no push
  since 2025-09, a niri crash report (niri #2250), and it would be a second
  clipboard owner running next to Noctalia.
- **Turn `cliphist` on by default.** Rejected: it only records history. It
  does not keep the clipboard alive after the source app closes.
- **Persist the primary selection too.** Rejected: upstream tools and the
  Hyprland wiki warn it breaks text selection in some apps.

## Consequences
- Keeping the clipboard alive now depends on Noctalia. Noctalia issue #3793
  ("history has it, `wl-paste` says empty", reported on niri) is fixed
  upstream by a patch, but it is not yet confirmed that the fix is in 5.1.0.
  If the VM reproduces it, we track the issue upstream; we do not add a
  second tool.
- With `wayland_shell = none` the sessions have no clipboard keep-alive; the
  operator's own dotfiles own that choice.
- Chromium ships only in the test VM. `mermaid-cli`, which pulls in
  `chromium`, is a separate curation question.
