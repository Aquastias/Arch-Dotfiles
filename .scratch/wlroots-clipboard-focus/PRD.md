# wlroots sessions: cross-toolkit clipboard + menus that keep focus

Status: ready-for-agent

Based on ADR 0147 (click-to-focus on both compositors, Noctalia's clipboard
keep-alive). Uses the [[Wayland Shell Companion]] / [[Desktop Environment
Adapter]] vocabulary.

## Problem Statement

An operator on a wlroots session (niri or Hyprland, with the Noctalia shell)
hits two problems:

- **Copy/paste between Chromium-based apps and Qt/GTK apps doesn't work
  reliably.** Text copied in Dolphin, pcmanfm-qt or a GTK app sometimes can't
  be pasted into Chromium or VSCodium, and the reverse also fails. On Wayland
  the app you copied from owns the clipboard contents, so once that app
  closes they are gone too.
- **Menus are hard to use.** Clicking File (or opening a context menu) and
  moving the cursor to an item can move focus away, and the menu closes before
  you can pick anything. Hyprland moves focus to whatever is under the cursor;
  niri doesn't, so the two sessions also behave differently.

## Solution

Both wlroots sessions behave the same way and predictably:

- The regular clipboard works in both directions between Chromium/Electron
  apps and Qt/GTK apps, and it survives the source app closing. Noctalia
  keeps it alive; this is pinned explicitly in the curated shell config.
- The primary selection (select text, middle-click to paste) works in both
  directions between the same apps while the source app is open.
- Keyboard focus changes only when you click (click-to-focus) on both
  compositors, so menus stay open until you pick an item or dismiss them.
- The work starts by reproducing both bugs in the VM. If the repro shows an
  XWayland path is involved, Chromium/Electron Wayland flags or
  `xwayland-satellite` are added then, not before.

## User Stories

1. As an operator, I want to copy text in a Qt app (Dolphin, pcmanfm-qt) and
   paste it into Chromium, so that browser forms take text from my files.
2. As an operator, I want to copy text in Chromium and paste it into a Qt
   app, so that URLs and snippets reach my file manager's rename/path fields.
3. As an operator, I want to copy text in a GTK app and paste it into
   Chromium, so that GTK tools work with the browser.
4. As an operator, I want to copy text in Chromium and paste it into a GTK
   app, so that the reverse direction works as well.
5. As an operator, I want to copy code in VSCodium and paste it into a Qt or
   GTK app, so that my editor isn't a clipboard dead end.
6. As an operator, I want to copy text in a Qt or GTK app and paste it into
   VSCodium, so that I can bring snippets into my editor.
7. As an operator, I want copy/paste between Chromium and VSCodium to work,
   so that two Chromium-based apps also talk to each other.
8. As an operator, I want text I copied to stay pasteable after I close the
   app I copied it from, so that "copy, close, paste" works like on
   KDE/GNOME.
9. As an operator, I want to select text in one app and middle-click paste
   it into another (Chromium ↔ Qt/GTK), so that primary selection works
   across toolkits.
10. As an operator, I want the clipboard to behave the same on niri and
    Hyprland, so that switching sessions changes nothing I rely on.
11. As an operator, I want clipboard persistence to need no extra package,
    so that the preset stays lean and has one clipboard owner (Noctalia).
12. As an operator, I want the keep-alive setting written explicitly in the
    curated shell config, so that a change to upstream's default can't
    silently turn it off.
13. As an operator, I want clicking File in any app to open a menu that stays
    open while I move to an item, so that I can pick the item.
14. As an operator, I want right-click context menus to stay open while I
    move the cursor, so that the item I aim for is the one that runs.
15. As an operator, I want nested submenus to stay open as I move into them,
    so that deeper menu items are reachable.
16. As an operator, I want keyboard focus to change only when I click
    another window, so that moving the mouse never steals focus.
17. As an operator, I want scrolling to still reach the window under the
    cursor on Hyprland, so that click-to-focus doesn't cost me
    hover-scrolling.
18. As an operator, I want niri and Hyprland to use the same focus model, so
    that my muscle memory carries across sessions.
19. As an operator, I want the fix to hold for any Chromium/Electron app, not
    only the ones in my profile, so that apps I add later behave too.
20. As a maintainer, I want the root cause reproduced before any fix, so
    that we don't ship speculative flags or packages.
21. As a maintainer, I want Chromium/Electron Wayland flags or
    `xwayland-satellite` added only if the repro shows an XWayland path, so
    that the preset gains nothing it doesn't need.
22. As a maintainer, I want a static guard asserting that the curated shell
    config pins the keep-alive, so that a config edit can't silently drop it.
23. As a maintainer, I want a static guard asserting that Hyprland's input
    config is click-to-focus, so that focus-follows-mouse doesn't creep back.
24. As a maintainer, I want the session prober to report a clipboard marker
    on every wlroots session, so that every VM run checks keep-alive and
    primary selection automatically.
25. As a maintainer, I want an agent-driven VM matrix run (both compositors ×
    Chromium/VSCodium ↔ Qt/GTK × regular/primary/after-close × menus), with
    its evidence recorded in the issues, so that "done" means observed, not
    assumed.
26. As a maintainer, I want Noctalia issue #3793 ("history has it,
    `wl-paste` says empty") checked against the shipped Noctalia version, so
    that if it reproduces we track it upstream instead of adding a second
    tool.
27. As an operator who picks `wayland_shell = none`, I want the sessions to
    seed nothing clipboard-related, so that my own dotfiles make that choice.

## Implementation Decisions

- **Scope**: both wlroots compositors in the desktop set (niri, Hyprland)
  that run the Noctalia [[Wayland Shell Companion]]. KDE is untouched.
- **Clipboard keep-alive**: the curated, stow-owned Noctalia `config.toml`
  sets `clipboard_keep_from_closed_apps = true` under `[shell]` explicitly.
  No `wl-clip-persist`, no default-on `cliphist` (ADR 0147).
- **Coverage**: the regular clipboard works in both directions and survives
  the source app closing. The primary selection works in both directions
  while the source app is open; it is not kept alive after the source closes
  (upstream tools warn it breaks apps).
- **Focus model**: Hyprland's curated input config moves from
  focus-follows-mouse to `follow_mouse = 2` (click-to-focus, hover-scroll
  kept). niri's config gets no `focus-follows-mouse` (it is click-to-focus
  already).
- **Reproduce first**: before changing anything, reproduce both bugs on both
  compositors in the VM and record which surfaces are native Wayland and
  which are XWayland. Only then decide:
  - If Chromium/Electron runs under XWayland and that causes the bug, seed
    Wayland platform flags for Chromium and VSCodium through the curated
    config (seeded to skel, stowable, same as other preset payload).
  - If niri needs X11 clients (and their clipboard), add
    `xwayland-satellite` to the niri adapter core. Otherwise it goes in a
    separate ticket.
  - If the popup problem remains after click-to-focus (e.g. XWayland menus on
    Hyprland), add targeted window rules. Grounded in the Arch/Hyprland wiki.
- **Noctalia #3793**: if the "history has it, `wl-paste` says empty" failure
  reproduces on the shipped Noctalia, record it and track it upstream; do
  not add a second clipboard owner.
- **Chromium in the VM**: Chromium is installed only in the test VM, not in
  any host profile.
- **Package/config decisions** trace to the Arch Wiki (clipboard, Chromium
  Wayland, Hyprland/niri input pages), fetched at implementation time, per
  repo rules.

## Testing Decisions

- Good tests assert behaviour you can see from outside (what the shipped
  config says, what a session actually pastes), not how the fix is built.
- **Static config guards (existing seam)**: extend the Noctalia stow bats
  suite with:
  - `config.toml`'s `[shell]` pins `clipboard_keep_from_closed_apps = true`
    (prior art: the `polkit_agent = true` guard);
  - Hyprland's input config sets `follow_mouse = 2`;
  - niri's input config has no `focus-follows-mouse`.
  If flags or `xwayland-satellite` land, add guards next to the existing
  adapter bats that list core packages.
- **Session prober (existing seam)**: the TEST-ONLY desktop-verify prober
  gets a clipboard probe that runs in each wlroots session:
  - copy a token to the regular clipboard and to primary with `wl-copy`;
  - kill the source;
  - assert the regular token is still pasteable;
  - emit a `CLIPBOARD-OK`/`CLIPBOARD-FAIL` marker, like the ADR 0100
    polkit/idle markers.
  The host side records it next to the existing probe markers. The prober's
  stubbed bats suite covers the OK and FAIL paths (prior art: the polkit
  marker tests).
- **Agent-driven VM matrix (existing seam, vm-agent control)**: on the niri
  and Hyprland desktop VM profiles, for Chromium and VSCodium ↔ Dolphin (or
  pcmanfm-qt) and a GTK app, check:
  - regular copy/paste in both directions;
  - paste after the source app closes;
  - middle-click primary in both directions;
  - File menu opens and an item can be selected in each app;
  - a right-click context menu and a submenu stay open.
  Screenshot evidence goes into the issue's `## Comments`, like the earlier
  closed wlroots tickets.

## Out of Scope

- Keeping the primary selection alive after the source app closes.
- Clipboard history UX (cliphist, Noctalia history panel settings).
- Adding `mermaid-cli` (and so `chromium`) to a host profile. That is a
  separate curation ticket.
- KDE Plasma sessions (Klipper already keeps the clipboard alive; KWin's focus
  model is untouched).
- Focus-follows-mouse as an option or toggle.
- `xwayland-satellite` on niri, unless the repro shows it's needed.

## Further Notes

- ADR 0147 is Proposed. Mark it Accepted once the VM matrix passes.
- wl-clip-persist was rejected for maintenance reasons: 1 contributor, no
  push since 2025-09, niri crash report #2250. Don't re-add it without
  revisiting ADR 0147.
- Relevant upstream refs: Noctalia shell config docs
  (`clipboard_keep_from_closed_apps`), Noctalia #3793, Hyprland wiki
  "Clipboard Managers".
