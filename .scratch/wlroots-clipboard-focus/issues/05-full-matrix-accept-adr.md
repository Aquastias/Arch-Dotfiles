# 05: Full VM matrix + accept ADR 0147

**What to build:** The complete agent-driven matrix passes on niri and
Hyprland: Chromium and VSCodium ↔ Qt (Dolphin/pcmanfm-qt) and GTK apps ×
regular in both directions / after source close / middle-click primary in
both directions × File menu, context menu, submenu. After it passes, ADR 0147
is Accepted and the PRD is done.

**Blocked by:** 02, 03, 04

**Status:** done

- [ ] Every matrix cell passes on both compositors; evidence in
      `## Comments`. (All but Hyprland after-close, waiting for 0.57.)
- [ ] Prober shows `CLIPBOARD-OK` on both sessions in the same run.
- [ ] ADR 0147 status → Accepted (done); PRD status → done (after 0.57).

## Comments

- 2026-09-28: ADR 0147 Accepted. Done: niri clipboard live 12/12 + after
  close 12/12; Hyprland live 12/12, probe `HYPR-CLIPBOARD-OK keep=xfail`;
  Hyprland menus for all 4 apps. Remaining: niri menus once a pointer
  injector is available, and Hyprland after-close once 0.57 lands (the probe
  flips from xfail to a hard check on its own).
- 2026-09-28 niri menus: pointer driven by `wlrctl` (virtual-pointer; built
  in the VM by the operator under ~/.cache, since /tmp is noexec). Moves are
  calibrated from the bottom-right corner, because top-left is niri's hot
  corner (overview). Columns at 50%, kitty as the window crossed.
  - kwrite: File → File Actions submenu stays open across kitty, focus stays
    on kwrite; File → New runs (Welcome → Untitled).
  - VSCodium: ≡ → File submenu stays open across a second VSCodium window;
    New Text File runs (Untitled-1).
  - Chromium: right-click context menu stays open across kitty; Save as…
    opens the portal dialog (org.gnome.Nautilus "All Files").
  - GTK (zenity, floating over tiled kitty): context menu stays open across
    kitty, focus stays on zenity; Paste lands the token (`GTKNIRITOK`).
  - Noctalia's 5-min idle lock fired during a stalled run; the run
    continued after `vm-agent unlock` + `idle off`.
- 2026-09-28 Hyprland menus, rerun with the **shipped** `input.lua` copied
  into the VM + `hyprctl reload` (follow_mouse 2, float_switch_override_focus
  0, anr_missed_pings 15; no config errors). Pointer via `wlrctl`.
  - kwrite: File Actions submenu held across kitty; New runs (→ Untitled).
  - VSCodium: File submenu held across kitty; New Text File runs
    (Untitled-2).
  - Chromium: context menu held across kitty; Save as… opens the portal
    dialog.
  - GTK (zenity floating): menu held across tiled kitty; Paste lands
    `GTKHYPRTOK`.
  - Also seen: after the reload, Hyprland's "updated to 0.56.2" news popup
    (`hyprland-donate-screen`) appeared and took focus. It is set off by
    `ecosystem.no_update_news` / `no_donation_nag` (wiki, default false);
    not set in the repo, a decision for the operator.
- Menus: all 4 apps pass on both compositors. Remaining: Hyprland
  after-close once 0.57 lands.
- 2026-09-28 closed by the operator. Hyprland after-close waits for 0.57
  (hyprwm/Hyprland#16117); the prober's `keep=xfail` turns into a hard check
  once 0.57 is installed, so no ticket needs to stay open for it.
