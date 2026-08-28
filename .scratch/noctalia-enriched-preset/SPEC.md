# Spec: Noctalia enriched-by-default plugin preset with a Rosé Pine palette

Status: ready-for-agent

Related: ADR 0093 (this feature — enriched preset + Rosé Pine default). Extends
and partly supersedes ADR 0090 (niri adapter + Noctalia preset; "glue only —
never theming" clause is lifted for this path). Builds on ADR 0087/0088
(`install-*.jsonc` file-level toggles + `/etc/skel` seeding), ADR 0021 (adapter
and Package Resolver read the same toggle file — no drift), ADR 0046
(combination matrix).

Depends on `.scratch/niri-noctalia-environment/` shipping first (this feature
grows the preset that spec introduced).

## Problem Statement

As the operator, the `noctalia` preset gives me a working shell but a spartan
one: a single plugin (Bitwarden) and, by deliberate rule, no theming at all — so
every fresh niri box greets me with Noctalia's stock look and an empty plugin
list. To get the desktop I actually work in — a palette I like, a launcher that
does SSH and file search, screen tooling, process and update management, laptop
power control — I hand-install a dozen plugins and set a theme after every
reinstall. I want that curated environment to *be* the default.

The catch: the plugins I want overlap. Several tools cover the same job (three
ways to capture a screen; four battery widgets; two update managers; a plugin
that duplicates the built-in launcher's calculator). A naive "install them all"
default would be redundant and confusing. I want the preset to make the
non-redundant choice for me, and still let me trim it.

## Solution

As the operator, the `noctalia` preset becomes **enriched by default** — still
one preset, not a second variant. On a fresh niri box I get:

- the **Rosé Pine** palette seeded as the default (one `[theme]` key in
  Noctalia's config), with Catppuccin / Tokyo-Night / Gruvbox / Nord one click
  away because they are built-in; a few control-center tiles switch between them
  via Noctalia's IPC;
- a **curated, overlap-free plugin set** (~22) installed and enabled, chosen so
  no two plugins do the same job;
- the **battery** pair (power management + widget) only when I am on a laptop;
- everything exposed as a **per-plugin bool** in `install-niri.jsonc`, so
  flipping toggles off recovers the lean shell — no new menu row.

I still get the ADR 0090 escape hatch: `niri_shell=none` seeds nothing.

## User Stories

1. As the operator, I want the `noctalia` preset to seed the **Rosé Pine**
   palette as the default, so that a fresh box already looks the way I want.
2. As the operator, I want the other four palettes (Catppuccin, Tokyo-Night,
   Gruvbox, Nord) available without extra install, so that I can switch on a
   whim — they are built-in, so nothing is seeded for them.
3. As the operator, I want one-click palette switching from the control center,
   so that I do not have to open Settings — implemented as `custom-shortcut`
   tiles calling `colorScheme set`, not a `config-swap` plugin.
4. As the operator, I want a curated plugin set installed and **enabled** by
   default, so that the desktop is ready to work, not a bare shell.
5. As the operator, I want the preset to make the non-redundant choice where
   plugins overlap, so that I do not get three tools for one job.
6. As the operator, I want `screen-toolkit` for capture + color-pick + record,
   so that I skip `color_picker` and the official `screen_recorder`.
7. As the operator, I want `wl-screen-mirror` kept for output mirroring, so that
   the one job screen-toolkit does not cover is still there (wl-mirror, not the
   Hyprland-only variant).
8. As the operator, I want `keymap` (view + edit) instead of
   `keybind-cheatsheet`, so that I have the superset, not both.
9. As the operator on a laptop, I want `battery-power-management` +
   `battery-widget`, so that I get charge limit, profiles, draw, and a readout —
   without `battery-threshold`, which duplicates the charge limit.
10. As the operator on a desktop, I want the battery plugins **absent**, so that
    I am not shown a battery UI for a machine with no battery.
11. As the operator, I want the built-in System-resources widget for glance
    metrics and `procmon` for interactive process management, so that I do not
    also install the redundant `system-monitor` plugin.
12. As the operator on Arch, I want `arch-updater` (pacman/AUR/flatpak) and not
    `system-updater`, so that I have one update manager, matched to my distro.
13. As the operator, I want the built-in launcher's calculator relied on, so
    that I do not install the redundant `calculator` plugin — while keeping
    `file-search`, `shell-command`, `ssh-launcher`, which add real providers.
14. As the operator, I want `config-swap` dropped, so that palette switching
    goes through built-in theming, not a generic file swapper.
15. As the operator, I want the remaining non-overlapping plugins
    (niri-active-workspace, niri-animations, niri-displays, sharednd,
    audio-switcher, drive-health, eyecare, mini-docker, custom-shortcut,
    udiskie, todo, wallpaper-switcher, cat, gamer-mode), so that the default
    covers the breadth I use.
16. As the operator, I want each plugin as a bool in `install-niri.jsonc`, so
    that I can trim the preset without a menu row per plugin.
17. As the operator, I want flipping all plugin bools off to recover the lean
    shell, so that the enriched default is not a one-way door.
18. As the operator, I want the plugin set fetched at **pinned refs** (one per
    source repo), so that installs are reproducible.
19. As the operator, I want both the official and community plugin sources
    registered, so that the community plugins the set draws on can be installed.
20. As the operator installing offline, I want a plugin fetch failure to skip
    that plugin with a warning, not fail the install (ADR 0090 precedent).
21. As the operator inspecting packages, I want the enriched preset's plugin and
    palette additions reported by the Package Resolver, so that I can see what a
    niri config installs and why.
22. As the maintainer, I want the underlying system tools each plugin wraps
    (hyprpicker, wl-mirror, smartctl, docker, fzf,
    powerprofilesctl, …) installed only for the plugins actually in the set, so
    that dropped plugins do not drag in orphan dependencies.
23. As the maintainer, I want bumping the pinned plugin refs to be editing two
    SHAs, so that keeping current is trivial.

## Implementation Decisions

**Seed the Rosé Pine palette (the one theming exception).** The adapter seeds a
Noctalia config fragment setting `[theme] source="builtin"`,
`builtin="Rosé Pine"` into `/etc/skel`. This is the single deliberate deviation
from ADR 0090's "seed glue, never look"; the rule holds otherwise — only the
default palette is seeded, and Noctalia self-generates the rest of its look. In
v5 this is a `[theme]` table in `/etc/skel/.config/noctalia/config.toml`
(`source = "builtin"`, `builtin = "Rosé Pine"`).

**Palette switching is built-in, surfaced via `custom-shortcut`.** No plugin
handles palette switching: the built-in theming system does (Settings, or
`qs -c noctalia-shell ipc call colorScheme set <Name>`). The preset seeds a
few `custom-shortcut` control-center tiles, one per shipped palette, each
calling that IPC. `config-swap` is **not** used (it is a generic file swapper,
not palette-aware).

**Curated plugin set, overlap resolutions.** The default set is (base):
`keymap`, `niri-active-workspace`, `niri-animations`, `niri-displays`,
`sharednd`, `screen-toolkit`, `wl-screen-mirror`, `arch-updater`,
`audio-switcher`, `procmon`, `cat`, `gamer-mode`, `drive-health`, `eyecare`,
`file-search`, `shell-command`, `ssh-launcher`, `mini-docker`,
`custom-shortcut`, `udiskie`, `todo`, `wallpaper-switcher`, plus the existing
`bitwarden`. Each
overlap cluster collapses to the non-redundant pick; the losers are **dropped**
from the default (still hand-installable):
- screen tooling: `screen-toolkit` (+ `wl-screen-mirror`) — drop `color_picker`,
  `screen_recorder`;
- keybinds: `keymap` — drop `keybind-cheatsheet`;
- battery: `battery-power-management` + `battery-widget` — drop
  `battery-threshold`;
- metrics: built-in System-resources + `procmon` — drop `system-monitor`;
- updates: `arch-updater` — drop `system-updater`;
- launcher: built-in calculator — drop the `calculator` plugin;
- palettes: built-in theming — drop `config-swap`.

**Laptop gating via an adapter-level `laptop` bool.** `install-niri.jsonc` gains
a `laptop` bool; the battery pair (`battery-power-management`, `battery-widget`)
is seeded only when it is true. The default is auto-detection via presence of
`/sys/class/power_supply/BAT*` (the installer runs in `arch-chroot`,
so `/sys` is live hardware); an explicit `laptop` bool in `install-niri.jsonc`
overrides the detection (unset ⇒ detect, set ⇒ wins). Chassis-type/DMI is not
used (flaky under VMs and mis-reported firmware). This is independent of the
host-profile system — no niri host profile is invented for it.

**Sourcing and pinning.** Plugins are **vendored at install time**, not
registered as runtime git sources: the adapter sparse-checks-out the plugin
folders from `noctalia-dev/community-plugins` + `official-plugins`
and copies them into the skel data dir. Because community-plugins is a single
repo, one pinned commit covers every community pick and one covers the official
picks: **two refs total**, bumped by editing two SHAs. The refs are pinned
**before merge** — the working branch may track upstream tips in dev,
but `main` lands pinned (reproducible installs where it matters, no churn while
iterating). Each plugin's wrapped system tool (hyprpicker is dropped with
color_picker; wl-mirror, smartctl, docker, fzf, powerprofilesctl, etc.) is
installed only for plugins in the set.

**`install-niri.jsonc` grows a bool per plugin, plus `laptop`.** Alongside the
existing `bitwarden`, `cava`, `cliphist`, the file gains one bool per shipped
plugin (default on) and `laptop`. The adapter and the Package Resolver read the
same file, so what installs and what is reported cannot drift (ADR 0021). No new
menu row: the single Environment control stays `niri_shell` on/off.

**Package Resolver.** The Noctalia preset's derived set is extended with the
plugin packages/system-tool deps and the palette seed, keyed on
`install-niri.jsonc` (+ `laptop`), so `explain-packages` shows the enriched set.

**v5 plugin-seeding mechanism (verified against the v5 source).** The v4-style
`~/.config/noctalia/plugins.json {enabled, sourceUrl}` registry is **dead** in
v5 — Noctalia ignores JSON. Seeding is declarative on-disk state, offline,
with **no** trust/checksum/signature/lockfile gate in the plugin loader. Per
plugin the adapter:
- sparse-checks-out the plugin's folder (`plugin.toml` + `.luau` entries) at a
  pinned ref and copies it to `/etc/skel/.local/share/noctalia/plugins/<dir>/` —
  the **data** dir (always-scanned local source, highest precedence), NOT
  `.config`;
- adds the plugin's canonical id (`"<author>/<plugin>"`, from its `plugin.toml`)
  to the `[plugins].enabled` list in
  `/etc/skel/.config/noctalia/config.toml`;
and once, for the whole preset, sets `[plugins].auto_update = "none"` (stops the
6-hourly background git fetch) and seeds **no** `settings.toml`. The state-dir
`~/.local/state/noctalia/settings.toml` loads last and would override the seed,
so it must not be shipped. No runtime `[[plugins.source]]` git source needed —
plugins are vendored, so first daemon start scans the data dir and enables them
offline. This replaces `niri.sh`'s `_niri_register_plugin` /
`_niri_seed_bitwarden_plugin` helpers.

**Bitwarden migrates off the dead path (precursor / part of this work).** The
existing Bitwarden seeding (ADR 0090) uses the same v4 path —
`.config/noctalia/plugins/bitwarden/` + `plugins.json` — so it does **not** load
on v5 Noctalia. It migrates to the v5 mechanism above (folder → data dir, id →
`[plugins].enabled`) by the same helper rewrite; Bitwarden is just the first
entry in the enabled set.

## Testing Decisions

A good test asserts external behavior at a module's public seam — the
packages/services a run installs, the files a run writes, the resolved reported
set — never internal wiring. The existing niri adapter test harness
(`tests/extras/niri-adapter.bats`) is the home for most of this.

- **niri adapter, enriched path** — extend `niri-adapter.bats`: under
  `niri_shell=noctalia` with default `install-niri.jsonc`, assert `config.toml`
  carries the `[theme]` Rosé Pine key and `[plugins].auto_update = "none"`; each
  default-on plugin's folder goes to `.local/share/noctalia/plugins/` and its
  id appears in `[plugins].enabled`; **no** `settings.toml` is seeded; each
  dropped plugin is **absent**; the two pinned source refs are the ones used; a
  plugin whose bool is false is neither copied nor enabled; an offline/failed
  fetch skips that plugin without failing the run.
- **Bitwarden v4→v5 migration** — assert Bitwarden is seeded via the v5 path
  (folder in `.local/share/noctalia/plugins/`, id in `[plugins].enabled`) and
  that the dead `.config/noctalia/plugins/bitwarden/` + `plugins.json` artifacts
  are **not** written.
- **Laptop gating** — in the same file: with `laptop=true` the battery pair is
  seeded; with `laptop=false` it is absent; the detection default resolves
  correctly for a battery-present vs battery-absent fixture.
- **Palette switch tiles** — assert the `custom-shortcut` tiles for the five
  palettes are seeded and call `colorScheme set` with the right names.
- **Package Resolver** — extend `tests/packages/resolver.bats`: the Noctalia
  preset derived set reports the enriched plugin/system-tool packages per
  `install-niri.jsonc` + `laptop`, and reports none of the dropped plugins.
- **Toggle honoring** — a spot check that flipping every plugin bool off reduces
  the run to today's lean shell (Bitwarden-only) + the palette seed.
- **VM integration** — the existing `desktop-verify` niri cell continues to come
  up; optionally assert Noctalia loads the enriched `plugins` config without a
  parse error (guards the v5 mechanism rewrite).

## Out of Scope

- A second `noctalia-enriched` preset variant — this is one enriched preset with
  per-plugin toggles (ADR 0093 rejected the variant).
- Seeding anything beyond the default palette of Noctalia's look (bar layout,
  widget placement, wallpaper) — first-run + dotfiles still own the rest.
- Switching palettes via `config-swap` or any file-swap mechanism — built-in
  theming only.
- Authenticating Bitwarden or any per-plugin credential/login — user's post-boot
  step (ADR 0090).
- Offering the enriched preset on Hyprland or any non-niri compositor.
- The heavy-recording path (official `screen_recorder`, GPU encoding) as a
  default — re-addable by hand; screen-toolkit is the default.
- Pinning each plugin to its own ref — a single per-source-repo ref is used.

## Resolved Questions

1. **v5 seeding mechanism** → `plugins.json` is dead; seed the plugin
   folder into `~/.local/share/noctalia/plugins/` + list the id in
   `[plugins].enabled` in `config.toml`, `auto_update = "none"`, ship no
   `settings.toml`. Purely declarative, offline, no trust gate. Verified against
   the v5 source. (See the v5-mechanism Implementation Decision.)
2. **`laptop` detection signal** → detect `/sys/class/power_supply/BAT*`
   presence, overridable by an explicit `laptop` bool in `install-niri.jsonc`.
3. **Enabled-by-default vs install-disabled** → enabled-by-default; the trust is
   bounded by pinning, the two sources, and the removable bools. Install-
   disabled would defeat the "ready on first login" goal.
4. **"niri active displays" identity** → `niri-active-workspace`, kept alongside
   `niri-displays` and `niri-animations` (all three from noctalia.dev/plugins).
5. **Pin timing** → pin-before-merge: the branch may track upstream tips;
   `main` lands the two refs pinned.

## Further Notes

- Palettes are a built-in Noctalia feature (`[theme]`), not plugins; Rosé Pine,
  Catppuccin, Tokyo-Night, Gruvbox, Nord all ship built in. Palette *variants*
  (e.g. Rosé Pine Moon) come from the community-palettes API, cached locally.
- `color_picker` wraps hyprpicker, which is wlroots-compatible — it is **not**
  Hyprland-only; it is dropped only because screen-toolkit subsumes it.
- v5 plugins are unsandboxed Luau executed as the user (installing = running a
  script); this is the trust surface behind the enabled-by-default decision.
- Sources: docs.noctalia.dev/noctalia/plugins, docs.noctalia.dev/noctalia/
  theming, github.com/noctalia-dev/{official,community}-plugins.
