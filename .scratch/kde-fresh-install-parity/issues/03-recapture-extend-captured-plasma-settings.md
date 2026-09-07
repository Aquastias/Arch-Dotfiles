# 03 — Re-capture & extend the Captured Plasma Settings

**What to build:** A fresh KDE login comes up on the operator's full setup, not
first-run: Activities (Default + Dev), the saved power profile, window rules,
Application Launcher favorites, the Activity Pager, and every panel widget's
individual settings are all present, and VLC is the default video player. This is
done by re-snapshotting the live `arch-combined` `~/.config` into the KDE
adapter's vendored skel and extending the captured set, konsave-style (verbatim
whole-file copy). Night light is finalized to follow sunrise/sunset offline.
(ADR 0111 / 0120)

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The existing vendored skel `.config` files are refreshed verbatim from the
      live `arch-combined` box.
- [ ] The captured set gains `kactivitymanagerdrc` (+ `kactivitymanagerd-statsrc`),
      `powerdevilrc`, `mimeapps.list`, `plasma-welcomerc`, `kwinrulesrc`.
- [ ] `powermanagementprofilesrc` remains the Plasma-6 migration stub;
      `powerdevilrc` carries the real power config.
- [ ] The captured `appletsrc` carries the operator's favorites, launchers,
      Activity Pager, and per-widget settings (fixes "pager missing" / "widget
      settings lost").
- [ ] `mimeapps.list` sets VLC as the default video handler.
- [ ] The captured `kwinrc` sets `[NightColor] NightColorMode=Location` with
      Râmnicu Vâlcea coordinates (≈ 45.10 N, 24.37 E) — sunrise/sunset compute
      offline and in a VM with no geoclue.
- [ ] The EDID-keyed `kscreenrc` / `kwinoutputconfig.json` remain excluded
      (ADR 0110).
- [ ] Stock/pure KDE seeds none of this (ADR 0112).
- [ ] `extras/kde-adapter.bats` asserts the new captured files land in the seed
      root, `kwinrc` carries the night-light keys, and pure KDE seeds nothing.
