# Hyprland Desktop Environment Adapter absorbs DE packages

Status: ready-for-agent

## Parent

`.scratch/host-package-cleanup/PRD.md`

## What to build

Make the Hyprland Desktop Environment Adapter own the Hyprland-derivable
packages, per the ADR 0021 amendment ("the adapter owns every package
derivable from `environment.desktop`"). This slice is purely additive to
the adapter — it does not yet remove the duplicates from the Host Configs
(that happens in the dedup slice; until then the overlap is a harmless
`--needed` no-op).

Extend the adapter's non-negotiable core to install `wl-clipboard` and
`xdg-desktop-portal-gtk`, and add three companion toggles in
`install-hyprland.jsonc`, each defaulting on: `screenshot` (installs
`grim` + `slurp`), `gtk-look` (installs `nwg-look`), and `wofi` (launcher,
reflecting the launcher actually used — alongside the existing
`fuzzel`/`rofi` options). DE-agnostic packages are deliberately NOT pulled
in here (`xdg-utils`, `papirus-icon-theme` stay in Host Configs);
`xorg-xinit` is not carried at all (pure-Wayland session).

## Acceptance criteria

- [ ] Adapter core installs `wl-clipboard` and `xdg-desktop-portal-gtk`.
- [ ] `install-hyprland.jsonc` exposes `screenshot`, `gtk-look`, and
      `wofi` toggles, defaulting on.
- [ ] `screenshot=true` resolves `grim` + `slurp`; `gtk-look=true`
      resolves `nwg-look`; `wofi=true` resolves `wofi`; each toggle
      contributes nothing when false.
- [ ] No DE-agnostic packages (`xdg-utils`, `papirus-icon-theme`) and no
      `xorg-xinit` are added to the adapter.
- [ ] `hyprland-adapter.bats` covers the new core packages and the three
      toggles on/off.

## Blocked by

None - can start immediately.
