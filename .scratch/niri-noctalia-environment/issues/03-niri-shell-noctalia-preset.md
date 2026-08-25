# 03 — `niri_shell` + Noctalia work preset

**What to build:** As the operator I get a menu-visible `environment.niri_shell`
choice (default `noctalia`, alt `none`) that turns a bare niri box into a
prepared work desktop. With `noctalia`, first login is immediately usable: the
Noctalia shell (bar, launcher, notifications, clipboard history, control center,
lock, wallpaper, OSD) autostarts, my kitty terminal and niri's native screenshot
are bound, and brightness works. With `none` I get bare niri that seeds nothing
(ticket 01's behaviour). Bitwarden is deliberately NOT here — it lands in ticket
04.

The preset (ADR 0090) installs `noctalia`, `kitty`, `brightnessctl` (all `extra`;
Noctalia v5 — `noctalia --daemon` is the autostart command) and seeds a
**minimal** `/etc/skel/.config/niri/config.kdl` glue only — `spawn-at-startup
"noctalia --daemon"` plus kitty + screenshot binds. It never seeds Noctalia's
theming/look (first-run + dotfiles own that). Preset component bools live in a new
`install-niri.jsonc` mirroring `install-kde.jsonc` (ADR 0087), read by both the
adapter and the resolver; ships `cava: false`, `cliphist: false`.

**Blocked by:** 01 — niri as a bare desktop (the adapter, enum, and menu must
exist to extend).

**Status:** ready-for-agent

- [ ] `environment.niri_shell` is an optional schema field (`noctalia` default |
      `none`), validated at config load; an unknown value aborts with its path;
      it is exported to the chroot the way `ENVIRONMENT_DESKTOP` is (no Install
      State field).
- [ ] Under `niri_shell=noctalia` the adapter installs `noctalia`, `kitty`,
      `brightnessctl` and seeds the minimal `/etc/skel` `config.kdl` glue
      (autostart Noctalia, bind kitty + native screenshot); it seeds no theming.
- [ ] Under `niri_shell=none` the adapter installs core only and seeds nothing.
- [ ] `install-niri.jsonc` exists with `cava`/`cliphist` bools (off) and is read
      by the adapter and the Package Resolver; the resolver reports the Noctalia
      preset as a derived set keyed on `niri_shell` + the file.
- [ ] The Guided Installer shows a `niri_shell` Environment row (enum, Display
      Labels Noctalia / none, default `noctalia`, override dot on change); the
      Environment summary names the niri shell.
- [ ] `environment.niri_shell` is registered as a matrix axis so
      `matrix_registry_assert` stays green.
- [ ] The niri adapter test is extended for both `niri_shell` values: preset
      packages + skel `config.kdl` glue present under `noctalia`; nothing beyond
      core under `none`.
