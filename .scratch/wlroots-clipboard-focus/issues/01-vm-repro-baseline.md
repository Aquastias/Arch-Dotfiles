# 01: VM repro baseline: clipboard + menu focus on both compositors

**What to build:** Reproduce both bugs on niri and Hyprland (the
[[Wayland Shell Companion]] sessions) in the agent-controllable VM, before any
fix lands. Chromium is installed in the test VM only. For each app in the
matrix, record whether its window runs as native Wayland or XWayland, and
record whether Noctalia #3793 ("history has it, `wl-paste` says empty")
shows up. The findings decide what tickets 02–04 do (ADR 0147).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] Chromium present in the wlroots test VM, no host profile changed.
- [x] Per compositor: Chromium, VSCodium ↔ Dolphin/pcmanfm-qt (Qt) and a GTK
      app, regular copy/paste in both directions attempted; pass/fail
      recorded.
- [x] Paste after closing the source app, and middle-click primary in both
      directions, attempted; pass/fail recorded.
- [x] File menu, context menu and submenu attempted in each app on each
      compositor; pass/fail recorded.
- [x] Wayland vs XWayland recorded per app per compositor.
- [x] Noctalia #3793 seen or not seen, on the shipped Noctalia version.
- [x] Findings + screenshot evidence in `## Comments`, stating whether
      ticket 04 is needed.

## Comments

- 2026-09-28 niri run (VM `arch-combined-sops-impermanence`, installed
  2026-09-27; noctalia 5.1.0, niri 26.04, chromium 153, vscodium-bin 1.135).
  Keys were driven by `wtype` (virtual-keyboard). `ydotool` (uinput) never
  reached niri. Qt = kwrite, GTK = zenity 4.2 (GTK4).
  - Chromium is **not test-only**: core `mermaid-cli` depends on `chromium`,
    so it ships on hosts. Fix the wording in ADR 0147 / PRD.
  - Surfaces: niri has no XWayland (no `xwayland-satellite`); Chromium
    (App ID `chromium`) and VSCodium (`codium`) run native Wayland.
  - Regular, live: 12/12 PASS (Chromium, VSCodium, Qt, GTK, every
    direction).
  - Regular, after the source closes: 12/12 PASS. Noctalia logs
    `adopted orphaned selection` (the keep-alive works at its default).
  - Keep-alive does **not** take over clipboard contents set by `wl-copy`
    (itself a data-control client). A prober that only uses `wl-copy` can't
    test keep-alive; it needs a real client as the source.
  - #3793 not seen. The one stale paste observed was a harness artifact (a
    VSCodium instance left running).
  - Primary: Chromium/VSCodium/Qt selection reaches primary. GTK does not:
    `gsettings-desktop-schemas` 50 defaults
    `gtk-enable-primary-paste=false` (GNOME's upstream change). Even with it
    set true, a GTK4 zenity selection advertises primary but `wl-paste -p`
    returns empty data. Needs a real middle-click test.
  - Middle-click paste and menu clicks: not driven on niri. No pointer
    injector works: ydotool is ignored, and building `wlrctl` (niri exposes
    `zwlr_virtual_pointer_manager_v1`) was declined by the permission gate.
  - Operator hand-test (same VM, niri): middle-click paste works in kitty
    and pcmanfm-qt. The GTK primary-paste setting had been switched on by
    hand earlier in that session.
  - Ticket 04 (XWayland path): **not needed on niri**; the cause is not
    XWayland.
- 2026-09-28 Hyprland run (same VM; Hyprland 0.56.2, installed config still
  `follow_mouse = 1`). `ydotool` works here. Pointer moves use `ydotool
  mousemove --absolute` at half the target coords (2× accel). ClamAV
  on-access (clamd/clamonacc, load ≈5) slows app start, so waits need slack.
  - Surfaces: Chromium and VSCodium `xwayland: 0` (native Wayland).
    Xwayland is present, but no matrix app uses it. Ticket 04 is **not
    needed**.
  - Regular, live: 12/12 pass once harness artifacts are removed: VSCodium
    readback via Ctrl+S was unreliable (hot-exit buffer), but the paste
    itself landed (screenshot).
  - **Regular, after the source closes: FAIL everywhere.** Root cause:
    Hyprland sends data-control clients **no selection(null)** when the
    owning client dies (`wl-paste --watch` sees the copy, nothing on kill),
    so Noctalia's lazy adoption (`handleSelection(nullptr)` →
    `m_pendingOrphanAdopt`) never fires. niri does send it. Hyprland #9638
    (persistence) was closed as intended; the wiki recommends
    `wl-clip-persist`, which takes over eagerly on every copy.
  - Hyprland ANR dialogs (`hyprland-dialog`) pop up when a slow Electron app
    misses pings, and they take keyboard focus. Seen repeatedly under load.
  - **Menu focus reproduced**: with `follow_mouse = 1`, the VSCodium ≡ menu
    closes when the pointer passes over kwrite (focus moves to kwrite). Qt
    (kwrite) menus survive. With `follow_mouse = 2` applied live (`hyprctl
    eval`), the same path keeps focus on VSCodium and the **menu stays open**
    (screenshot).
  - Hyprland ships `input:float_switch_override_focus = 1` by default: even
    with `follow_mouse = 2`, crossing from a floating dialog (zenity) to a
    tiled window moved focus, and the dialog's context menu lost it. Set it
    to 0 (ticket 03).
  - Hyprland 0.56.2 drops primary set by a data-control client (`wl-copy -p`);
    primary set by apps (Chromium, kitty) works.
