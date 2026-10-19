# 02: Hyprland drops the packaged uwsm session

**What to build:** On every Hyprland install the packaged
`hyprland-uwsm.desktop` session never reaches disk: the Hyprland adapter adds
a pacman `NoExtract` for it before installing Hyprland, and removes any copy
already present. start-hyprland stays the sole Hyprland session under every
greeter — needed because noctalia-greeter scans `/usr/share` unconditionally
and cannot be pinned to the curated session dir ([ADR 0158], [ADR 0070]).

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] pacman config carries the `NoExtract` entry on Hyprland hosts only.
- [ ] No `hyprland-uwsm.desktop` exists after install or after a hyprland
      package upgrade.
- [ ] The entry survives impermanence rollback of `/etc`.
- [ ] VM run (Hyprland profile) shows the curated session list unchanged.
