Status: ready-for-agent

# Power Profile selector

## Parent

`.scratch/bluetooth-power-fonts-toggles/spec.md` (ADR 0080)

## What to build

Add `options.power.profile` — a choice field `none | power-profiles-daemon |
tuned` (default `power-profiles-daemon`) in its own root-level **Power**
Configuration Category. This is the enum generalisation of the toggle-derived
pattern: the *value* selects which daemon package is injected into the
Effective Config's `system_programs` at assembly time and which service is
enabled (`power-profiles-daemon.service` / `tuned.service`). `tuned`
additionally pulls `tuned-ppd` so a KDE/Hyprland profile applet keeps working.
`none` injects nothing.

The selector is DE-agnostic: it works with or without KDE (`powerprofilesctl`
/ `tuned-adm` drive it headlessly). `power-profiles-daemon` is only an
optional dep of Powerdevil today, so this key genuinely adds it even on KDE.
The Package Resolver reports the derived program as `source=power`.

End-to-end path: schema allowlist key → accessor → seed default → menu field
(Power category) + `menu_enum_options` entry → pure resolver (value → package
+ service, `tuned` → `+tuned-ppd`) → assembly-time injection → Package
Resolver provenance → matrix Axis Registry classification.

## Acceptance criteria

- [ ] `options.power.profile` renders as a choice of `none` /
      `power-profiles-daemon` / `tuned` in its own Power category; default
      `power-profiles-daemon`, normalised-out when default.
- [ ] `power-profiles-daemon` → installs ppd + enables its service; `tuned`
      → installs `tuned` + `tuned-ppd` + enables `tuned.service`; `none` →
      nothing injected.
- [ ] Package Resolver / explain-packages reports the derived program as
      `source=power`.
- [ ] `options.power.profile` is classified `inert|light` in the matrix Axis
      Registry.
- [ ] Choice equal to the default normalises out; a saved profile stores
      only the delta.
- [ ] `power.bats` (pure resolver spec) plus a `guided-menu.bats` extension
      pass under `tests/run.sh --fast`.

## Blocked by

- None - can start immediately
