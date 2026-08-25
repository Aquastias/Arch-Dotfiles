# 01 — niri as a bare desktop

**What to build:** As the operator I can select `niri` in the installer and get
a working, bare scrollable-tiling compositor. Selecting `niri` (alone or
alongside KDE/Hyprland) installs a core-only niri Desktop Environment Adapter and
lets me log into a niri session — no shell, no seeded config; my dotfiles own the
rest, exactly like Hyprland today. This is the walking skeleton for the whole
feature; `niri_shell` and the Noctalia preset layer on top later (ticket 03).

Scope is core-only (ADR 0021/0062, ADR 0090): the adapter installs the `niri`
package (which pulls `seatd`), both XDG portals (GNOME for screencast + GTK), the
polkit agent, and the Wayland clipboard bridge, and enables `seatd`. It authors
**no** session file and **no** aquamarine DRM pin — the `niri` package ships its
own session and niri handles GPU selection itself.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `niri` is a valid `environment.desktop` value; KDE/Hyprland/niri and any
      subset validate; an install with `niri` selected runs its adapter by
      convention with no Environment Runner change.
- [ ] The niri adapter installs the core set and enables `seatd`; it writes no
      session file and no DRM pin.
- [ ] The Guided Installer offers `niri` in the desktop multi-select with a
      correct Display Label.
- [ ] The Package Resolver reports niri's core as its own derived set, visible in
      `explain-packages` / the guided derived section.
- [ ] Widening the desktop enum auto-adds niri cells to the combination matrix;
      `matrix_registry_assert` stays green.
- [ ] Config-load resolution/validation tests cover niri as a desktop value
      (prior art: existing desktop cases in the environment-resolution /
      environment-validation bats).
- [ ] A new niri adapter test (clone of the Hyprland adapter harness) asserts the
      core packages + `seatd` enable, run with pacman/systemctl stubbed and
      `ROOT` redirected to a tmpdir.
- [ ] The VM `desktop-verify` harness gains a niri cell that logs into the niri
      session and asserts `===NIRI-SESSION-OK===`.
