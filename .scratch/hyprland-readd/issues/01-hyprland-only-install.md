# Hyprland-only install, end-to-end

Status: ready-for-agent

## Parent

`.scratch/hyprland-readd/PRD.md` (ADR 0062, 0005, 0021)

## What to build

An operator can select Hyprland as the only desktop — from a Host Profile or the
Guided Installer — and the install produces a working Hyprland session behind a
greetd + greetd-tuigreet login. `hyprland` becomes a valid `environment.desktop`
value, is offered in the guided Environment desktop list, and renders as
`Hyprland` in menus and summaries. The restored Hyprland Desktop Environment
Adapter installs only the working-session core (compositor, both portals, polkit
agent, Wayland clipboard bridge) — no companion applications and no `qt6ct-kde`,
no `aur` field. When KDE is absent from the resolved desktop set the adapter
installs and enables greetd with a tuigreet config that launches the compositor
directly, and ships the direct-launch wayland-session override (exec is the
compositor binary, never `start-hyprland`) where it wins the DM's session scan.
The Environment Runner dispatches to the adapter by directory convention with no
DE literal added.

## Acceptance criteria

- [ ] `hyprland` passes Environment validation; an unknown desktop still errors
- [ ] Guided Environment desktop selection offers `hyprland`
- [ ] Display Label formatter renders `hyprland` as `Hyprland`
- [ ] Adapter installs exactly the 5-package working-session core
- [ ] Adapter installs no companion packages and no `qt6ct-kde`
- [ ] greetd + greetd-tuigreet installed and enabled when KDE is absent
- [ ] Session override exec launches the compositor directly, never `start-hyprland`
- [ ] Environment Runner dispatches to the adapter by convention (no DE literal)
- [ ] `hyprland-adapter.bats` restored (sibling of `kde-adapter.bats`) and green;
      environment-resolution, environment-validation, display-label, menu-enum
      tests updated and green

## Blocked by

- None — can start immediately
