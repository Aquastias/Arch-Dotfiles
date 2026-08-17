Status: ready-for-agent

# General services & fonts: bluetooth, power, and a font catalog

Spec for extending the Guided Installer with a curated Font Catalog, a
Bluetooth Service toggle, and a Power Profile selector — generalising the
toggle-derived System Program pattern (ADR 0079) to a bool, an enum, and a
multi-select. Governed by **ADR 0080** (extends 0079, amends 0076).

## Problem Statement

As an operator building a machine through the Guided Installer, I cannot
discover or configure three things I always end up wanting:

- **Fonts** are buried. Today the shared font set lives as an unstructured
  Host Core `packages.repo.fonts` list; the only way to add a font I want
  (e.g. a Nerd-patched monospace for my Powerlevel10k prompt) is to already
  know its exact package name and type it into the Packages free-text
  entry. There is no way to *see* a curated list, and no way for a
  default-*off* font (like Monaspace) to appear as a checkable option at
  all — an unchecked row cannot exist for a package that isn't declared.
- **Bluetooth** works only by accident. On KDE, `bluez` + BlueDevil arrive
  transitively via `plasma-meta`, but nothing enables `bluetooth.service`,
  so a fresh KDE machine boots with Bluetooth *off* until I enable it by
  hand. On a non-KDE install nothing installs `bluez` at all. There is no
  switch.
- **Power management** has no representation. `power-profiles-daemon` is
  only an optional dependency of Powerdevil, so it is never actually
  installed; I get no battery/performance profile switching out of the box,
  and no way to choose `tuned` or opt out.

## Solution

Three additions to the Guided Installer, each mirroring the just-shipped
**Printing Service** so the installer stays consistent:

- **Font Catalog** — a curated multi-select of fonts (modelled on the
  Kernels multi-select) living as a leaf in the **General Category**. I
  TAB-check the fonts I want from an enumerated list; sensible fonts are
  pre-checked, and default-off fonts still appear as unchecked-but-checkable
  rows. This *replaces* the Host Core font list as the single font home.
- **Bluetooth Service** — a single on/off **Cycle Field** in its own
  **Bluetooth** Configuration Category (default on). When on, it installs
  the Bluetooth daemon layer and enables `bluetooth.service`; when off,
  Bluetooth is genuinely absent. It never installs a GUI — the desktop owns
  that.
- **Power Profile** — a choice of `none | power-profiles-daemon | tuned`
  in its own **Power** Configuration Category (default
  `power-profiles-daemon`). The chosen backend is installed and its service
  enabled; the choice works with or without KDE.

Plus: on Hyprland, a Bluetooth tray applet (`blueman`) is provided, but it
stays invisible inside KDE sessions (where BlueDevil is the tray).

## User Stories

1. As an operator, I want a curated list of fonts I can check on and off in
   the Guided Installer, so that I don't have to memorise package names.
2. As an operator, I want sensible fonts pre-checked, so that an untouched
   install already has good coverage.
3. As an operator, I want default-*off* fonts (like Monaspace) to still
   appear as unchecked rows, so that I can discover and enable them without
   typing a package name.
4. As an operator with a Powerlevel10k prompt, I want Nerd-patched
   monospace fonts, so that my prompt's glyphs and icons render correctly.
5. As an operator, I want the Noto family — including the CJK/"asian" fonts
   — installed by default, so that I don't see unrecognised glyphs (tofu)
   in the browser.
6. As an operator, I want Microsoft-metric and Microsoft core fonts
   available, so that web pages requesting Verdana/Georgia/Tahoma render as
   intended (which `ttf-liberation` alone does not cover).
7. As an operator, I want the font selection to be the single source of
   truth, so that a font is never installed via two competing mechanisms.
8. As an operator on a non-KDE or server install, I still want a coherent
   default font set, so that fonts don't silently disappear when no desktop
   pulls them transitively.
9. As an operator, I want the Font Catalog to live under General, so that I
   don't have to hunt through a separate category for it.
10. As an operator, I want to see which fonts are overridden from the
    defaults (the `●` dot), so that I know what I changed.
11. As an operator, I want a Bluetooth on/off switch in the Guided
    Installer, so that I control whether Bluetooth is set up.
12. As an operator, I want the Bluetooth switch on by default, so that the
    common laptop/desktop case works with no interaction.
13. As an operator on KDE, I want the Bluetooth toggle to actually enable
    `bluetooth.service`, so that BlueDevil works at first boot instead of
    being dormant.
14. As an operator who turns Bluetooth off, I want `bluez` genuinely absent,
    so that "off" means not installed, not merely a disabled service.
15. As an operator on Hyprland, I want a Bluetooth tray applet, so that I
    can manage devices without a Plasma session.
16. As an operator running a KDE session on a KDE+Hyprland machine, I want
    to see only BlueDevil (not `blueman`), so that I don't get two competing
    Bluetooth trays.
17. As an operator on a KDE-only machine, I do not want `blueman` (and its
    GTK dependencies) installed at all, so that my system stays lean.
18. As an operator, I want the Bluetooth toggle to install only the daemon
    layer (never a GUI), so that a KDE box isn't polluted with GTK cruft.
19. As an operator, I want to choose my power-management backend, so that I
    can pick `power-profiles-daemon`, `tuned`, or none.
20. As an operator, I want `power-profiles-daemon` as the default, so that
    KDE's Powerdevil profile switcher works out of the box (it doesn't
    today, since ppd is only an optional dep).
21. As an operator who doesn't use KDE, I want power management to still
    work, so that I can drive it from the CLI (`powerprofilesctl` /
    `tuned-adm`) or a Hyprland bar.
22. As an operator who chooses `tuned`, I want `tuned-ppd` installed too, so
    that my desktop's profile applet keeps working instead of going dead.
23. As an operator who wants no power daemon, I want a `none` option, so
    that nothing power-related is installed.
24. As an operator, I want each new option to show its live value and
    options in the detail pane, so that choices stay discoverable without
    guessing.
25. As an operator, I want Bluetooth to render as an in-place on/off flip
    (a Cycle Field), so that I don't drill into a values submenu for a bool.
26. As an operator inspecting what will be installed, I want the Package
    Resolver / `explain-packages` to attribute the derived programs to their
    toggle (`source=bluetooth`, `source=power`), so that I can trace why a
    package lands.
27. As an operator, I do not want `cups`/`bluetooth` system programs
    appearing twice, so that each toggle-owned program has exactly one menu
    home (the Bluetooth toggle, like the Printing toggle, is filtered out of
    the Packages system-programs picker).
28. As an operator saving a profile, I want my non-default font/bluetooth/
    power choices persisted as a delta over Host Core, so that a saved
    profile stays layered.
29. As an operator whose choices equal the defaults, I want them
    normalised out, so that an untouched option leaves no override noise in
    the saved profile.
30. As a maintainer, I want the new options classified in the matrix Axis
    Registry, so that the generator refuses to run until they're accounted
    for.
31. As a maintainer, I want pure-function specs for each resolver, so that
    the value→package mappings are verified headlessly without a VM.

## Implementation Decisions

- **Three new schema keys**, added to the closed profile schema allowlist so
  a typo aborts at load: `options.bluetooth.enabled` (bool),
  `options.power.profile` (enum), `options.fonts` (array). Each gets a typed
  accessor and a seed default.
- **Pattern reuse.** Each feature gets a pure resolver module modelled on
  the Printing resolver: JSON in, derived programs/packages out, no
  filesystem or TTY. Bluetooth and Power inject a derived **System Program**
  into the Effective Config's `system_programs` at assembly time (both the
  `--profile` assembly path and the Guided emit path), exactly as the
  Printing toggle injects `cups`.
- **Bluetooth** is a bool **Cycle Field** in its own **Bluetooth**
  Configuration Category (default `true`, normalised-out when true). Its
  derived program installs `bluez` + `bluez-utils` and enables
  `bluetooth.service`. The program is filtered from the Packages →
  system-programs picker so the toggle is its sole menu home. On KDE the
  `bluez` install is a `--needed` no-op (plasma-meta already pulls it); the
  toggle's material effect there is enabling the service.
- **Power** is the enum generalisation of the pattern: `options.power.profile`
  ∈ `{none, power-profiles-daemon, tuned}` (default `power-profiles-daemon`)
  in its own **Power** Configuration Category. The value selects which
  daemon package is injected and which service is enabled; `tuned`
  additionally pulls `tuned-ppd`. `none` injects nothing. This is the first
  toggle-derived key whose *value* (not merely its truthiness) picks the
  package.
- **Font Catalog.** `options.fonts` is a curated multi-select whose option
  set is enumerated in the single menu options source (alongside kernels,
  bootloaders, etc.), rendered comma-joined, and resolved to packages before
  pacstrap. It lives as a leaf in the **General Category** (ADR 0080's
  deliberate re-broadening of 0076). The default-checked set: `noto-fonts`,
  `noto-fonts-emoji`, `noto-fonts-cjk`, `noto-fonts-extra`,
  `ttf-liberation`, `ttf-dejavu`, `ttf-ms-fonts`, `ttf-jetbrains-mono-nerd`,
  `ttf-iosevka-nerd`, `ttf-firacode-nerd`. Selectable-but-off:
  `otf-monaspace-nerd`, `ttf-sazanami`. Plain `ttf-fira-code` is dropped in
  favour of `ttf-firacode-nerd`.
- **Single font home.** `packages.repo.fonts` is removed from Host Core; the
  catalog's defaults are the shared baseline, and the desktop/laptop
  profiles inherit fonts through it. The font resolver is repo+AUR aware:
  repo fonts join the pacstrap set; the lone AUR font (`ttf-ms-fonts`) is
  routed to the Primary User's paru pass.
- **Package Resolver provenance.** The resolver reports the derived
  bluetooth/power programs with their source tag (`source=bluetooth`,
  `source=power`), joining the printing entry as the derived System Programs
  it surfaces.
- **`blueman` on Hyprland.** `blueman` is owned by the Hyprland Desktop
  Environment Adapter — installed iff Hyprland is in the selected desktop
  set, so a KDE-only host never gets it. Its autostart entry carries
  `NotShowIn=KDE`, so the applet is suppressed in KDE sessions (BlueDevil is
  the tray there) and shown in Hyprland sessions. It coexists with BlueDevil
  without conflict on a KDE+Hyprland box.
- **Matrix classification.** All three new `_MENU_FIELDS` paths are
  registered `inert|light` in the Axis Registry — they add packages/services
  with no disk/boot/pool *combination* content, so they are not new matrix
  axes (the Printing precedent).

## Testing Decisions

A good test here asserts **external behavior** — "given this config, these
programs/packages are derived and these menu rows appear" — never internal
function wiring. Seams, fewest and highest:

- **Seam 1 — pure config-function bats (primary).** New specs
  `fonts.bats`, `bluetooth.bats`, `power.bats` mirroring the existing
  `tests/config/printing.bats`: feed a config JSON, assert the resolver's
  derived programs/packages, the enum→package+service mapping
  (`none`/`ppd`/`tuned`/`+tuned-ppd`), the font catalog's resolved set
  including the `ttf-ms-fonts` AUR routing, the seed defaults, and
  schema-allowlist accept/reject. No VM, no chroot.
- **Seam 2 — guided menu render bats (existing).** Extend
  `tests/config/guided-menu.bats` for the new rows and categories (General
  fonts leaf, Bluetooth + Power categories, canonical category ordering,
  the bluetooth Cycle Field), and `guided-controller.bats` for the
  bluetooth system-programs picker filter — the same seam the Printing
  service used.
- **Seam 3 — matrix registry assert (existing, no new test).** The registry
  assertion already fails until each new field path is classified; the three
  `inert|light` rows satisfy it, and the always-on `print-summary-setu.bats`
  guard exercises the new fields for free.

Prior art: `tests/config/printing.bats` (pure resolver spec),
`tests/config/guided-menu.bats` and `tests/config/post-install.bats`
(menu/derived-program specs), `tests/matrix/print-summary-setu.bats`
(set -u guard).

## Out of Scope

- **Bluetooth device pairing / management UX** beyond providing the daemon
  and a tray applet — pairing is a runtime user task.
- **Power auto-switching / tuned custom profiles** — only backend selection
  and service enablement are in scope; tuning rules are not authored here.
- **Chassis (laptop vs desktop) auto-detection** to vary defaults — the
  static desktop/laptop Host Profiles remain the only laptop/desktop split;
  defaults are flat.
- **A standalone Fonts Configuration Category** and **a Packages fonts leaf**
  — both were considered and rejected in favour of the General leaf (ADR
  0080).
- **`TLP` and other power backends** beyond `power-profiles-daemon` /
  `tuned` — the enum is deliberately closed.
- **A dedicated `blueman` unit bats** — the autostart/`NotShowIn=KDE`
  behavior is verified via the existing guided-extras VM smoke rather than a
  new seam.
- **Font rendering configuration** (fontconfig aliasing, hinting,
  sub-pixel) — only which font packages install is in scope.
- **Post-install runtime management** of any of these (a running system's
  font/bluetooth/power changes) — this is install-time configuration only.

## Further Notes

- Governed by **ADR 0080** ("Toggle-derived services generalized:
  bluetooth, power, fonts"), which extends ADR 0079 (bool → enum +
  multi-select) and amends ADR 0076 (General re-broadened from identity to
  identity + fonts). New glossary terms in `CONTEXT.md`: **Bluetooth
  Service**, **Power Profile**, **Font Catalog**; the **General Category**
  entry is amended.
- KDE already pulls `bluez`, `bluez-qt`, BlueDevil, and Powerdevil via
  `plasma-meta`; `power-profiles-daemon` is only an *optional* dep of
  Powerdevil, so these toggles genuinely add behavior (a service enable, a
  daemon install) even on KDE rather than duplicating packages.
- `ttf-liberation` provides metric-compatible substitutes only for Arial,
  Times New Roman, and Courier New; it does not cover Verdana, Georgia,
  Tahoma, Trebuchet, Comic Sans, or Impact — which is why `ttf-ms-fonts` is
  retained in the default set.
- Build is to land as three per-feature commits (`feat(fonts)`,
  `feat(bluetooth)`, `feat(power)`), each running `tests/run.sh --fast` plus
  its new bats.
