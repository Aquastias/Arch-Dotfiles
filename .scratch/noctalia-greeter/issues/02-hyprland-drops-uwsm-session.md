# 02: Hyprland drops the packaged uwsm session

**What to build:** On every Hyprland install the packaged
`hyprland-uwsm.desktop` session never reaches disk: the Hyprland adapter adds
a pacman `NoExtract` for it before installing Hyprland, and removes any copy
already present. start-hyprland stays the sole Hyprland session under every
greeter — needed because noctalia-greeter scans `/usr/share` unconditionally
and cannot be pinned to the curated session dir ([ADR 0158], [ADR 0070]).

**Blocked by:** None (can start immediately).

**Status:** done

- [x] pacman config carries the `NoExtract` entry on Hyprland hosts only.
- [x] No `hyprland-uwsm.desktop` exists after install or after a hyprland
      package upgrade.
- [x] The entry survives impermanence rollback of `/etc`.
- [x] VM run (Hyprland profile) shows the curated session list unchanged.

## Comments

VM `desktop/hyprland` (local HEAD d0c5ad7), 2026-10-19: `NoExtract` line in
pacman.conf; `/usr/share/wayland-sessions` holds only `hyprland.desktop`, also
after `pacman -S hyprland` reinstall (package lists `hyprland-uwsm.desktop`).
Profile is not impermanent; rollback safety is by construction (@blank is
taken after extras run).
