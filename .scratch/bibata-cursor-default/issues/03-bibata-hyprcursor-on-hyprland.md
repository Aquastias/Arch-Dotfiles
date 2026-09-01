# 03 — Bibata Modern Ice hyprcursor default on Hyprland

**What to build:** a fresh Hyprland box uses Bibata Modern Ice as a real
hyprcursor cursor, with the Xcursor theme as the XWayland/legacy fallback. The
Hyprland adapter installs `bibata-cursor-git` (one package shipping both formats)
and the seeded `hyprland.conf` sets the hyprcursor theme/size env plus the
Xcursor fallback env, with the standard default-icon path seeded. Edits the
Noctalia-wired `hyprland.conf`, so it depends on the shell rewrite.

**Blocked by:** `noctalia-shared-shell` ticket 03 (Hyprland boots the shared
Noctalia environment — the `hyprland.conf` rewrite)

**Status:** ready-for-agent

- [ ] `bibata-cursor-git` is declared in the Hyprland adapter's `aur` list and
      lands via the paru pass when Hyprland is selected.
- [ ] The seeded `hyprland.conf` sets `HYPRCURSOR_THEME=Bibata-Modern-Ice` +
      `HYPRCURSOR_SIZE=24` (primary) and keeps `XCURSOR_THEME` as the fallback.
- [ ] `~/.icons/default` is seeded to inherit `Bibata-Modern-Ice`.
- [ ] Setting `HYPRCURSOR_THEME` alone applies the cursor on a fresh login; if a
      nudge is required, an `exec-once` is added rather than a manual step.
- [ ] `hyprland-adapter.bats` asserts the hyprcursor env and the aur declaration.
