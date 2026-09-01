# 03 — Hyprland boots the shared Noctalia environment

**What to build:** selecting Hyprland with `wayland_shell=noctalia` brings up the
same prepared desktop niri does. The Hyprland adapter installs the Noctalia
preset via the shared module (shell + kitty + brightnessctl + playerctl +
enabled companions + shared-core plugin deps), seeds a Noctalia-wired
`hyprland.conf` + the shared `config.toml` + the Noctalia helper scripts into
`/etc/skel`, and vendors the shared-core plugins. `hyprlock` is dropped from
Hyprland core (Noctalia locks via `ext-session-lock-v1`). The shared launcher and
lock keys route through Noctalia IPC (the `wofi` launcher bind is gone); the
config autostarts `noctalia --daemon` + the enable-plugins one-shot via
`exec-once`; Hyprland-native extras (scratchpad, mouse drag) stay. Under
`wayland_shell=none` the adapter seeds nothing (bare, symmetric with bare niri).
This supersedes ADR 0096's app-layer stance.

**Blocked by:** 01, 02

**Status:** ready-for-agent

- [ ] `hyprland + wayland_shell=noctalia` installs the Noctalia preset packages.
- [ ] `chroot.sh` stages the **same** Noctalia payload into the Hyprland curated
      dir that it already stages for niri — `.config/noctalia/config.toml` and
      `.local/bin/noctalia-*`, alongside the Hyprland `hyprland.conf` — from the
      one repo source (today it stages only `hyprland.conf` for Hyprland).
- [ ] The Noctalia-wired `hyprland.conf`, shared `config.toml`, and helper
      scripts are seeded to `/etc/skel` and equal the single repo source; the
      seeded `config.toml` is byte-identical to the one niri seeds (same source).
- [ ] Shared-core plugins are vendored; the enable-plugins one-shot is seeded.
- [ ] The plugin split is respected: **no `niri-*` plugin is vendored or enabled
      on Hyprland**. The seeded `config.toml` lists shared-core only (no slice
      ids), so it stays byte-identical to niri's while the enabled set reflects
      the compositor. (The `hypr-*` slice itself arrives in ticket 04.)
- [ ] `hyprlock` is **not** installed; launcher/lock keys drive Noctalia IPC.
- [ ] `wayland_shell=none` seeds nothing and installs no Noctalia set (bare).
- [ ] The existing Hyprland core plumbing is intact (seatd, portals, polkit,
      wl-clipboard, blueman, start-hyprland DRM session, aquamarine hybrid pin,
      curated sessions).
- [ ] `hyprland-adapter.bats` covers the noctalia and none paths, the seeded
      files, the vendored plugins, and hyprlock's absence.
