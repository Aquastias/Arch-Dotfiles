# Hyprland Desktop Environment Adapter absorbs DE packages

Status: done

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

- [x] Adapter core installs `wl-clipboard` and `xdg-desktop-portal-gtk`.
- [x] `install-hyprland.jsonc` exposes `screenshot`, `gtk-look`, and
      `wofi` toggles, defaulting on.
- [x] `screenshot=true` resolves `grim` + `slurp`; `gtk-look=true`
      resolves `nwg-look`; `wofi=true` resolves `wofi`; each toggle
      contributes nothing when false.
- [x] No DE-agnostic packages (`xdg-utils`, `papirus-icon-theme`) and no
      `xorg-xinit` are added to the adapter.
- [x] `hyprland-adapter.bats` covers the new core packages and the three
      toggles on/off.

## Blocked by

None - can start immediately.

## Comments

- Done (TDD). Adapter core line gains `xdg-desktop-portal-gtk` +
  `wl-clipboard`; three on-by-default toggles added to
  `install-hyprland.jsonc` and resolved by `_companion`
  (`screenshot`→`grim slurp`, `gtk-look`→`nwg-look`, `wofi`→`wofi`).
- `_companion` refactored to varargs (multi-pkg toggles) + hyphen-safe key
  lookup (`jq '.[$k]'` — `.gtk-look` would parse as subtraction).
- Tests: +1 core-packages case, +6 toggle on/off cases in
  `hyprland-adapter.bats` (13/13 green). Shellcheck clean.
