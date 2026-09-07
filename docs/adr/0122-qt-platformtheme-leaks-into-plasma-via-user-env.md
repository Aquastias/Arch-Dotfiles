# QT_QPA_PLATFORMTHEME leaks into Plasma via the systemd --user env

---
Status: accepted. **Extends ADR 0102/0104/0116** (the App Theming Bridge and
its dual-session isolation). Those kept Noctalia's palette out of KDE via the
*files* (drop `kcolorscheme`, `kdeglobals` Plasma-owned) and out of GTK-under-
Plasma (the Breeze reset autostart). This closes the remaining vector: the Qt
platform-theme **environment variable**. **Traced live in the `arch-combined`
VM** (hyprland → logout → same-boot Plasma), fix verified end-to-end with
screenshots + pixel sampling.
---

ADR 0102 sets `QT_QPA_PLATFORMTHEME=qt6ct` **per-compositor** (niri's
`environment {}`, Hyprland's `env =`) rather than in `~/.config/environment.d/`,
specifically so it reaches the compositor session but not Plasma. That reasoning
holds for a *file* — environment.d would apply to a Plasma session too — but it
misses a runtime path:

- niri/Hyprland export their session env into the **shared `systemd --user` /
  D-Bus activation environment** on startup (Hyprland runs
  `dbus-update-activation-environment`; the systemd import is standard compositor
  startup). VM-verified: a **fresh Hyprland boot** already shows
  `QT_QPA_PLATFORMTHEME=qt6ct` in `systemctl --user show-environment`.
- The `systemd --user` instance is **per-user, not per-seat-session** — it
  survives a graphical logout and lives for the whole boot. So after
  hyprland → logout → **same-boot** login to Plasma, the variable is still in the
  user manager, and Plasma launches its apps (plasmashell forks + D-Bus/systemd
  activation) with `QT_QPA_PLATFORMTHEME=qt6ct` inherited.
- Result: Qt/Kirigami KDE apps take the **qt6ct** platform theme, which points
  at Noctalia's `qt6ct/colors/noctalia.conf` (ADR 0102) — Catppuccin. VM-
  verified: System Settings rendered a Breeze QWidget frame (`kdeglobals`, still
  clean) but its **Kirigami footer painted `#1e1e2e`** (Catppuccin Mocha base).
  `kdeglobals` is untouched — this is purely the env var, not a file leak.

A plain reboot into Plasma is clean (the user manager restarts fresh), which is
why ADR 0104/0116's reboot-based VM testing never caught it — the leak needs a
**same-boot** compositor→Plasma transition.

## Decision

Strip `QT_QPA_PLATFORMTHEME` at the start of every Plasma session on a combined
box, before plasmashell, so Plasma falls back to its native `plasma-integration`
platform theme (Breeze). The KDE adapter (`kde.sh`) seeds a Plasma env script
`~/.config/plasma-workspace/env/kde-unset-qt-platformtheme.sh`:

```sh
unset QT_QPA_PLATFORMTHEME
systemctl --user unset-environment QT_QPA_PLATFORMTHEME 2>/dev/null || true
```

Why this shape:

1. **`~/.config/plasma-workspace/env/*.sh` is sourced by `startplasma` before
   plasmashell** (VM-verified with a sentinel export that reached both
   plasmashell's `/proc/<pid>/environ` and `systemctl --user show-environment`).
   So the `unset` reaches plasmashell and every app it forks.
2. **`systemctl --user unset-environment` clears both the systemd user env AND
   the D-Bus activation env** (VM-verified) — so apps launched via
   D-Bus/systemd activation, not just plasmashell forks, are covered.
3. **Combined-box-gated** (`ENVIRONMENT_DESKTOP` carries `niri`/`hyprland`),
   mirroring the GTK Breeze reset (ADR 0116). On a pure-KDE box no compositor
   ever sets the var, so the script would be dead payload; on a combined box a
   fresh KDE boot makes it a harmless no-op (var unset).
4. **Seeded, never stowed** — via `kde.sh`'s `_seed_write` into `/etc/skel`, the
   established KDE-side seed pattern (beside `kde-gtk-breeze-reset.desktop`). The
   compositor side is unchanged: niri/Hyprland still set the var for their own
   apps; this only undoes the leak on the Plasma side.

## Considered options

- **Unset via a KDE autostart** (like the GTK reset) — rejected: autostart runs
  *after* plasmashell has already started and inherited the polluted env; the
  platform theme is read at app startup, so it must be stripped in `env/*.sh`
  (pre-plasmashell), not autostart.
- **Move `QT_QPA_PLATFORMTHEME` to `environment.d`** so it is managed uniformly —
  rejected: it would then reach Plasma *by design* (worse), and would still not
  reach Hyprland reliably (the original ADR 0102 reason — `start-hyprland` is not
  the systemd/uwsm session).
- **Stop the compositor exporting it into the user manager** — rejected: the
  export is built into compositor startup (`dbus-update-activation-environment`);
  suppressing it is fragile and would break the var reaching the compositor's own
  D-Bus/portal-activated apps.
- **Gate on a reboot between sessions** — not a mechanism; the leak is real for
  the documented same-boot path and must be handled in the Plasma session.

## Consequences

- **Plasma stays Breeze after a same-boot compositor→Plasma switch** — KDE apps
  (System Settings footer VM-verified back to Breeze `#202326`) no longer inherit
  Noctalia's qt6ct palette. Completes the isolation triangle: `kdeglobals`
  (ADR 0104), GTK theme (ADR 0116), Qt platform-theme env (this ADR).
- **Bounded, additive surface:** one combined-box-gated seed in `kde.sh`
  (guarded by `kde-adapter.bats`), no change to the compositor side, no change to
  pure-KDE or pure-compositor boxes.
- The compositor session is unaffected — its apps still get qt6ct/Noctalia.
