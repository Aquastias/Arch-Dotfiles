# 01 — Live Theme Bridge scaffolding + Qt6 live-repaint

**What to build:** the [[Live Theme Bridge]] end-to-end, with the simplest
nudge, so that changing the Noctalia theme *mid-session* repaints a **running**
Qt app without a relaunch. A new curated `noctalia-theme-bridge` script runs for
the compositor session's lifetime, `inotifywait`s Noctalia's generated color
files, and on each change `touch`es the top-level `qt6ct.conf` — firing qt6ct's
dir-watcher so `applySettings()` re-runs and open Qt apps repaint. The script is
autostarted on both compositors and reaches fresh installs for free (the
installer already stages/seeds `.local/bin/noctalia-*` by glob — no installer
change needed).

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `noctalia-theme-bridge` exists as a curated `.local/bin` script, executable,
      matching the `noctalia-*` glob so it is staged (both adapters) and seeded to
      `/etc/skel` with no installer edit.
- [ ] The script watches Noctalia's generated color files
      (`qt6ct/colors/noctalia.conf`, `gtk-{3,4}.0/noctalia.css`) via `inotifywait`
      and reacts to every write (covers both the cycle tile and the Noctalia GUI).
- [ ] On a color-file change it `touch`es the top-level `qt6ct.conf`; a running Qt
      app (pcmanfm-qt) repaints to the new palette without relaunch — verified by
      hand on the `arch-combined` VM.
- [ ] niri's curated `autostart.kdl` and Hyprland's curated `autostart.lua` each
      spawn the bridge at compositor startup, beside `noctalia --daemon`.
- [ ] `inotify-tools` is added to `noctalia_preset_packages`, grounded against the
      Arch Wiki.
- [ ] `noctalia-stow.bats` asserts the script is present + executable and the
      autostart line is wired on both adapters.
- [ ] The resolver bats assert `inotify-tools` resolves under niri and hyprland
      (part of the Noctalia preset base).
- [ ] Runs only from the compositor autostart (never a Plasma session); writes
      only compositor-private `qt6ct.conf` — no cross-session leak.
