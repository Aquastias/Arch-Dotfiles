Status: ready-for-agent

# Bluetooth Service toggle + Hyprland tray

## Parent

`.scratch/bluetooth-power-fonts-toggles/spec.md` (ADR 0080)

## What to build

Add `options.bluetooth.enabled` — a bool **Cycle Field** (default `true`,
normalised-out when true) in its own root-level **Bluetooth** Configuration
Category, a service-enablement twin of the Printing Service. When on, a
derived `bluetooth` System Program is injected into the Effective Config's
`system_programs` at assembly time (both the `--profile` assembly path and
the Guided emit path); it installs `bluez` + `bluez-utils` and enables
`bluetooth.service`. When off, Bluetooth is genuinely absent.

The toggle owns only the daemon layer — never a GUI. It is filtered out of
the Packages → system-programs picker so it has exactly one menu home, and
the Package Resolver reports the derived program as `source=bluetooth`. On
KDE the `bluez` install is a `--needed` no-op (plasma-meta already pulls it);
the material effect there is enabling the service, which nothing does today.

Separately, provide a Hyprland Bluetooth tray: the Hyprland Desktop
Environment Adapter installs `blueman` (iff Hyprland is in the selected
desktop set, so a KDE-only host never gets it) and writes its autostart entry
with `NotShowIn=KDE`, so the applet is suppressed in KDE sessions (BlueDevil
is the tray there) and shown in Hyprland sessions.

End-to-end path: schema allowlist key → accessor → seed default → menu field
(Bluetooth category, Cycle Field) → pure resolver → assembly-time injection →
picker filter → Package Resolver provenance → Hyprland adapter blueman +
autostart → matrix Axis Registry classification.

## Acceptance criteria

- [ ] `options.bluetooth.enabled` renders as a Cycle Field in its own
      Bluetooth category; default `true`, normalised-out when true.
- [ ] On → `bluetooth` program injected into `system_programs`; installs
      `bluez` + `bluez-utils` and enables `bluetooth.service`. Off → absent.
- [ ] `bluetooth` is filtered from the Packages → system-programs picker.
- [ ] Package Resolver / explain-packages reports the derived program as
      `source=bluetooth`.
- [ ] `blueman` installs only when Hyprland is selected; never on a KDE-only
      install.
- [ ] `blueman`'s autostart carries `NotShowIn=KDE` (suppressed in KDE
      sessions, shown in Hyprland sessions); coexists with BlueDevil on
      KDE+Hyprland without conflict.
- [ ] `options.bluetooth.enabled` is classified `inert|light` in the matrix
      Axis Registry.
- [ ] `bluetooth.bats` (pure resolver spec) plus `guided-menu.bats` /
      `guided-controller.bats` extensions pass under `tests/run.sh --fast`.

## Blocked by

- None - can start immediately
