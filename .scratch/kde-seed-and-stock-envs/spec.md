# Spec: KDE settings seed, stock environment variants, unified Meta+X close

Status: ready-for-agent

Traces to ADR 0110 (compositor resolution autodetected), ADR 0111 (KDE adapter
seeds captured Plasma settings), ADR 0112 (stock environment variants), ADR 0113
(close window on Meta+X). Supersedes the look portions of ADR 0088/0104 as those
ADRs record.

## Problem Statement

The operator built a complete KDE Plasma setup on the `arch-combined` reference
box — a custom dark colour scheme, four virtual desktops, kwin plugins and a
tiling layout, faster animations, a 30-minute lock, klipper history, a full panel
of widgets, a DetailTree file dialog, and a Meta+X close shortcut — and wants a
fresh install to boot straight into that setup instead of Plasma's first-run
defaults. Today the KDE [[Desktop Environment Adapter]] only seeds a minimal
Breeze-Dark look (ADR 0088), so all of that work is lost on reinstall.

Two more gaps sit alongside it:

- There is no way to install a **stock** environment — the installer's KDE and
  wlroots adapters are opinionated (curated apps + KDE-config seed on KDE; the
  Noctalia [[Wayland Shell Companion]] on niri/Hyprland). The operator sometimes
  wants the distro's own defaults with nothing added, to build up from scratch.
- The close-window key is inconsistent: `Mod+Q` on niri/Hyprland, `Alt+F4` on
  KDE. The operator wants one reflex — Meta+X — everywhere.

Finally, the operator asked whether any default Plasma widget needs a dependency
program the installer seed is missing, and asked for the desktop to come up at
this monitor's native resolution and refresh (a 4K panel that advertises up to
144 Hz).

## Solution

From the operator's perspective:

- A fresh KDE login lands on the exact setup captured from `arch-combined` —
  colours, virtual desktops, widgets, shortcuts, lock, klipper, file-dialog view
  — not first-run.
- A single **stock** switch (guided toggle, or a committed `*-pure` profile)
  installs upstream-stock: bare Plasma, or a bare niri/Hyprland compositor, with
  no dotfiles, no extra apps, and no Noctalia.
- Meta+X closes the focused window in KDE, niri and Hyprland alike.
- The monitor comes up at its native resolution and refresh with no host-specific
  configuration, on any hardware.
- The widget-dependency question is answered: nothing is missing — the Plasma
  shell's dependency tree already pulls every default widget's backend.

## User Stories

1. As the operator, I want my captured KDE colour scheme seeded into a fresh
   install, so that Plasma opens in my custom dark theme, not stock Breeze.
2. As the operator, I want my four virtual desktops (2 rows) restored, so that my
   workspace layout is ready on first login.
3. As the operator, I want my kwin plugins (dim-inactive, fall-apart, wobbly
   windows) enabled, so that window effects match my setup.
4. As the operator, I want my kwin tiling layout (25/50/25) restored, so that
   tiling works without re-drawing it.
5. As the operator, I want my animation-duration factor (0.75) seeded, so that
   the desktop feels as snappy as I set it.
6. As the operator, I want my panel widget layout restored from
   `plasma-org.kde.plasma.desktop-appletsrc`, so that every widget I placed is
   present on first login.
7. As the operator, I want my screen-lock timeout (30 min) seeded, so that the
   session locks on my schedule.
8. As the operator, I want my klipper history settings (100 items, URL grabber)
   seeded, so that clipboard behaviour matches my setup.
9. As the operator, I want my Dolphin, Konsole, and KFileDialog preferences
   seeded, so that file management opens the way I configured it.
10. As the operator, I want my empty-session login mode seeded, so that a fresh
    login opens to the desktop, not a restored session.
11. As the operator, I want the captured settings copied verbatim (konsave-style),
    so that UUID-keyed state (virtual desktops, tiling) stays self-consistent.
12. As the operator, I want the monitor/output config excluded from the seed, so
    that resolution stays autodetected per machine and never black-screens.
13. As the operator, I want the seed to survive on a combined KDE+compositor host,
    so that my Plasma colours and the Noctalia compositor palette coexist without
    fighting.
14. As the operator, I want to install a pure KDE (Plasma shell only), so that I
    get stock Breeze with no curated apps and no seeded settings.
15. As the operator, I want to install a pure niri, so that I get the bare niri
    compositor with no Noctalia and no seeded config.
16. As the operator, I want to install a pure Hyprland, so that I get the bare
    Hyprland compositor with no Noctalia and no seeded config.
17. As the operator, I want a single `stock` toggle in the [[Guided Installer]]
    Environment category, so that I can choose stock without editing files.
18. As the operator, I want committed `kde-pure`, `hyprland-pure`, and
    `niri-pure` [[Host Profile]]s, so that `--profile <name>-pure` installs a
    stock environment unattended.
19. As the operator, I want a pure environment to still enable the Bluetooth
    service, so that a host daemon toggle is not entangled with DE config.
20. As the operator, I want the Guided Installer's read-only `derived` view and
    `explain-packages` to reflect a stock install's reduced package set, so that
    the reports stay truthful.
21. As the operator, I want Meta+X to close the focused window in KDE, so that it
    matches my compositors.
22. As the operator, I want Meta+X to close the focused window in niri, replacing
    Mod+Q, so that the close key is consistent.
23. As the operator, I want Meta+X to close the focused window in Hyprland,
    replacing Mod+Q, so that the close key is consistent.
24. As the operator, I want KDE to keep Alt+F4 as well as Meta+X, so that the
    cross-platform reflex still works.
25. As the operator, I want the monitor to come up at its native resolution and
    refresh via compositor autodetection, so that no host-specific mode is baked
    into the shared config.
26. As the operator, I want assurance that no default Plasma widget is missing a
    dependency, so that every widget works out of the box.
27. As a maintainer, I want the KDE settings captured as vendored files in the
    adapter, so that the seed is reproducible like the Noctalia preset.
28. As a maintainer, I want `environment.stock` to thread into the chroot as an
    env var read by the adapters, so that no [[Environment Runner]] or dispatch
    change is needed.
29. As a maintainer, I want the `*-pure` profiles validated against the closed
    schema, so that a malformed pure profile aborts at load.
30. As a maintainer, I want each behaviour tested at an existing seam, so that the
    feature is verifiable headless without a VM.

## Implementation Decisions

**KDE captured-settings seed (ADR 0111).** The KDE [[Desktop Environment
Adapter]] gains a vendored set of captured Plasma config files, copied verbatim
into `/etc/skel` (konsave's mechanism: fixed file list, whole-file copy, no
parsing). Captured `~/.config/` files: `kdeglobals`, `kwinrc`, `plasmarc`,
`plasmashellrc`, `plasma-org.kde.plasma.desktop-appletsrc`, `kglobalshortcutsrc`,
`kcminputrc`, `klipperrc`, `kscreenlockerrc`, `ksmserverrc`, `dolphinrc`,
`konsolerc`, `plasma-localerc`. The custom colour scheme rides inline in
`kdeglobals` (no separate `.colors` file). The adapter's hand-written Breeze-Dark
heredocs for the four look files are replaced by the captured versions; ADR 0088's
non-look seeds (Plasma Welcome hidden, Baloo on, SDDM theme drop-in, GTK cursor
inherit) are retained. Excluded from capture: `kscreenrc` and
`kwinoutputconfig.json` (monitor/output — autodetected, ADR 0110), akonadi/PIM
runtime state, caches. On a combined host the App Theming Bridge's
`kcolorscheme` template stays off (ADR 0104 unchanged) so Noctalia never merges
into `kdeglobals`.

**Stock environment lever (ADR 0112).** Add `environment.stock` (bool, default
`false`) to the [[Environment Config]] and the closed schema. It resolves and
validates in `lib/config/environment.sh` mirroring `wayland_shell`, and threads
into the chroot as `ENVIRONMENT_STOCK` (like `ENVIRONMENT_WAYLAND_SHELL`) — no
runner change. When true, each selected desktop installs upstream-stock:

- KDE adapter → install the `plasma-meta` shell only; skip `apps_list`,
  `apps_extra`, `plugins`, `aur` (ADR 0087) and the entire captured/first-run
  seed (ADR 0088/0111).
- niri / Hyprland adapters → behave as `wayland_shell: none` (ADR 0097): bare
  compositor + session, seed nothing. `stock` forces the `none` path.

Host daemons stay independent: the Bluetooth service toggle (default-on, ADR
0080) applies regardless of `stock`.

**Package Resolver (ADR 0112).** `lib/packages/resolver.sh` reports the stock
reduction — under `stock`, the KDE app/seed sets and the Noctalia preset sets are
absent — so `explain-packages` and the guided `derived` view stay truthful.

**Guided exposure (ADR 0112).** A `stock` [[Cycle Field]] (bare bool, flips in
place) in the Environment Configuration Category, default off.

**Committed `*-pure` profiles (ADR 0112).** `kde-pure`, `hyprland-pure`,
`niri-pure` under `.installer/hosts/`, each modelled on `minimal`
(`packages.inherit: false`, `host_programs: []`), a single `environment.desktop`,
and `environment.stock: true`.

**Meta+X close (ADR 0113).** niri `conf.d/keybinds.kdl`:
`Mod+X { close-window; }` replaces `Mod+Q`. Hyprland `conf.d/keybinds.lua`:
`SUPER + X` → `window.close()` replaces `SUPER + Q`. KDE: the captured
`kglobalshortcutsrc` carries `Window Close=Alt+F4\tMeta+X,Alt+F4,Close Window`.
`Mod+Q` is freed on the compositors, not repurposed.

**Resolution (ADR 0110).** No change — niri (`output` omitted) and Hyprland
(`mode = "preferred"`) already autodetect; no resolution is seeded. The KDE seed
excludes the output config for the same reason.

**Widget-dependency audit (finding, no change).** Every default Plasma widget's
backend is a hard dependency inside the `plasma-meta` tree (`libksysguard` →
`lm_sensors`; `plasma-vault` → `gocryptfs`; plus `plasma-nm`, `bluedevil`,
`plasma-pa`, `powerdevil`, `kdeplasma-addons` — all required-by `plasma-meta`).
No package is added to any seed.

## Testing Decisions

Good tests here assert **external behaviour** at the highest existing seam — what
lands in a seed root, what the resolver reports, whether a profile validates —
never private helper internals. Prefer the existing `.bats` seams; add cases to
them rather than new files.

- **KDE adapter** — `tests/extras/kde-adapter.bats`, driving `kde.sh` with
  `KDE_SEED_ROOT` pointed at a temp dir (existing prior art). Assert: the full
  captured file list appears under `etc/skel/.config`; `kdeglobals` carries the
  custom colours; `kglobalshortcutsrc` binds Meta+X to Window Close; under
  `ENVIRONMENT_STOCK=1` (or the stock bool) the shell installs but no captured
  seed and no app sets are written.
- **Compositor adapters** — driving `niri.sh`/`hyprland.sh` with
  `NIRI_SEED_ROOT`/`HYPR_SEED_ROOT`. Assert: the seeded keybind file binds `Mod+X`
  to close (and no longer `Mod+Q`); under stock, nothing is seeded (the existing
  `wayland_shell: none` behaviour).
- **Environment resolution/validation** —
  `tests/config/environment-resolution.bats` and `environment-validation.bats`.
  Assert: `environment.stock` resolves to a bool, defaults false, validates its
  value set, and threads `ENVIRONMENT_STOCK`; an unknown value aborts with a
  clear message (mirror the `wayland_shell` cases).
- **Package Resolver** — `tests/packages/resolver.bats`. Assert: a stock KDE
  config reports the plasma shell only (no `kde-shell` app sets); a stock
  compositor reports no Noctalia preset set.
- **Profile validation** — `tests/vm/profile-validate.bats`. Assert: `kde-pure`,
  `hyprland-pure`, `niri-pure` validate against the closed schema and resolve to a
  single-desktop, stock, no-inherit config.

## Out of Scope

- Forcing 4K/144 (or any specific mode) into the seed — resolution stays
  autodetected (ADR 0110); a per-host `output`/`monitor` override remains the
  operator's own, uncommitted, choice.
- Seeding `kscreenrc` / `kwinoutputconfig.json` (host-specific monitor state).
- Any change to the App Theming Bridge / Noctalia isolation on combined hosts
  (ADR 0104 stays as-is).
- Adding widget-dependency packages — the audit proved none are missing.
- A per-desktop `full|pure` modifier on the `environment.desktop` array — `stock`
  is a single global bool by decision (ADR 0112).
- Bluetooth configuration changes — `AutoEnable=true` is already bluez's default;
  the existing toggle already enables the service.
- Migrating akonadi/PIM state or user data.

## Further Notes

- The captured KDE settings are a point-in-time snapshot of `arch-combined`;
  re-tweaking Plasma means re-capturing, exactly like the vendored Noctalia cache
  (ADR 0109) and plugin set (ADR 0093).
- `environment.stock` and an explicit `wayland_shell: noctalia` are
  contradictory; the resolver treats `stock` as authoritative for the selected
  desktops (documented at the validation site).
- CONTEXT.md glossary, README/REFERENCE, and adapter comments (compact style)
  update alongside the code to match ADRs 0110–0113.
