# 03: XDG user dirs generated on niri/Hyprland (incl. Projects)

**What to build:** After logging into a niri or Hyprland session, the user has
the standard XDG user dirs (`~/Desktop`, `~/Downloads`, `~/Documents`, `~/Music`,
`~/Pictures`, `~/Videos`, `~/Templates`, `~/Public`) and a `~/Projects` folder —
the [[Wayland Session XDG Dirs]] behaviour (ADR 0131). KDE is unchanged (it
already generates them via XDG autostart). Generation is idempotent.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The [[Wayland Shell Companion]] preset seeds `user-dirs.dirs` — full
      standard set in explicit English paths plus a declarative non-standard
      `XDG_PROJECTS_DIR` — into `/etc/skel` **and** the existing user's `$HOME`
      (skel misses already-created users).
- [ ] The per-compositor autostart runs `xdg-user-dirs-update` then creates
      `~/Projects`, on both niri and Hyprland, beside the shell daemon /
      [[Live Theme Bridge]] launch.
- [ ] Scope is compositor-only; nothing new runs under KDE.
- [ ] The preset bats suite asserts the seeded `user-dirs.dirs` and the
      per-compositor autostart entries.
