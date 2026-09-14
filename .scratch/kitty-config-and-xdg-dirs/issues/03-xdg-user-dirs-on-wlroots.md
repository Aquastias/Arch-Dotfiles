# 03: XDG user dirs generated on niri/Hyprland (incl. Projects)

**What to build:** After logging into a niri or Hyprland session, the user has
the standard XDG user dirs (`~/Desktop`, `~/Downloads`, `~/Documents`,
`~/Music`, `~/Pictures`, `~/Videos`, `~/Templates`, `~/Public`) and a
`~/Projects` folder —
the [[Wayland Session XDG Dirs]] behaviour (ADR 0131). KDE is unchanged (it
already generates them via XDG autostart). Generation is idempotent.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] A seeded `noctalia-xdg-user-dirs` script (riding the [[Wayland Shell
      Companion]] preset's `.local/bin/noctalia-*` skel seed) runs
      `xdg-user-dirs-update` (standard set from the stock English defaults),
      then creates `~/Projects` and declares a non-standard `XDG_PROJECTS_DIR`.
      Idempotent.
- [ ] Both compositor autostarts call it (niri + Hyprland), beside the shell
      daemon / [[Live Theme Bridge]] launch.
- [ ] Run at login as the user, it reaches existing and new users alike — no
      per-`$HOME` seed (the preset is skel-only, ADR 0095).
- [ ] Scope is compositor-only; nothing new runs under KDE.
- [ ] `noctalia-stow.bats` asserts the script's shape and the per-compositor
      autostart entries.
