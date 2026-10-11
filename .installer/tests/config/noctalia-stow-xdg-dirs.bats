#!/usr/bin/env bats
# Tests: session XDG dirs (split from noctalia-stow.bats;
# shared setup in noctalia-stow-helpers.bash)

load noctalia-stow-helpers


# ── Wayland Session XDG Dirs: generate XDG dirs + ~/Projects (ADR 0131) ──────
# niri/Hyprland don't run /etc/xdg/autostart, so xdg-user-dirs-update never
# fires as it does under Plasma. A seeded noctalia-xdg-user-dirs script, called
# from the compositor autostart at login, closes the gap for all users.

@test "noctalia-xdg-user-dirs updates dirs + Projects (ADR 0131)" {
  [ -x "$XDGDIRS" ]
  grep -q 'xdg-user-dirs-update' "$XDGDIRS"          # standard set
  grep -q 'mkdir -p "$HOME/Projects"' "$XDGDIRS"     # the non-standard folder
  grep -q 'XDG_PROJECTS_DIR' "$XDGDIRS"              # declared for resolvers
}

@test "both compositors autostart the XDG-dirs generator (ADR 0131)" {
  grep -q 'noctalia-xdg-user-dirs' "$NAUTO"
  grep -q 'noctalia-xdg-user-dirs' "$HAUTO"
}
