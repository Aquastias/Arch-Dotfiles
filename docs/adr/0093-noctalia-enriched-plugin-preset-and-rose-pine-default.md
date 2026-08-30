# Noctalia enriched-by-default plugin preset and a seeded Rosé Pine palette

---
Status: accepted. Extends ADR 0090 (niri adapter + Noctalia preset); supersedes
ADR 0090's "glue only — never Noctalia's theming" clause, scoped to this preset.
Verified end-to-end by a full VM install: niri renders (via virgl — a Wayland
compositor rejects software EGL, so the VM harness gives it an accel3d GPU), the
plugin set vendors + enables, and the seeded config.toml is honoured on boot.
---

ADR 0090 shipped the `noctalia` preset as a near-bare shell plus one plugin
(Bitwarden). This ADR grows that same preset into a **curated work
environment**: a seeded palette and a vetted plugin set chosen so their features
do not overlap. It stays **one preset**, enriched by default — not a second
`noctalia-enriched` variant. Every plugin is a file-level bool in
`install-niri.jsonc`, so "lean" is recoverable by toggling off; there is no new
menu row and no second code path to maintain.

## Seeded palette (supersedes 0090's no-theming clause)

Noctalia palettes are a **built-in** feature (`[theme] source`/`builtin`), not a
plugin. Rosé Pine, Catppuccin, Tokyo-Night, Gruvbox and Nord all ship built in.
The preset now seeds `[theme] source="builtin", builtin="Rosé Pine"` into skel's
Noctalia config — the single deliberate deviation from ADR 0090's rule that the
adapter seeds glue and never look. The rule holds everywhere else: only the
default palette is seeded; Noctalia self-generates the rest of its look on first
run. The other four palettes need no seeding — they are switchable natively
(Settings → Theming, or `noctalia msg color-scheme-set builtin <Name>`; v5 is a
native binary, so the old `qs -c noctalia-shell` Quickshell IPC is gone).
For a one-click affordance we seed the (singleton) `custom-shortcut` tile wired
to a seeded script that cycles the five palettes via `msg color-scheme-set` — no
`config-swap` (a generic file swapper, **not** palette-aware). We do not seed
`control_center.shortcuts` (that array would replace the built-in Control Center
defaults), so placing the tile is a one-time user step.

## Seeded look tweaks (beyond the palette)

The palette is not the only look the preset fixes. A short, **portable** set of
prefs captured from a curated live session is seeded into the same config.toml:
`[theme]` gains `mode="dark"`, `community_palette`, `wallpaper_scheme`; plus
`[audio] enable_overdrive`, `[dock] enabled`/`icon_size`, `[nightlight]`, and
`[shell] app_icon_colorize`. config.toml is the fresh-boot base; the UI's
state-dir settings.toml overrides it once the user edits it. **Host-bound**
surfaces are deliberately excluded — lockscreen widget geometry keyed to an
output name (`@Virtual-1`, pixel positions, resolution) and wallpaper paths do
not survive a move to real hardware, so they stay Noctalia/user-owned.

## Plugin set and the overlap resolutions

Each cluster below collapses to the non-redundant pick; the rejected members are
dropped from the default set (still installable by hand):

- **Screen tooling** — `screen-toolkit` (all-in-one picker + record + OCR/QR/
  annotate) subsumes both `color_picker` (hyprpicker — wlroots, so *not*
  Hyprland-only, but redundant here) and official `screen_recorder`. Kept:
  `screen-toolkit` + `wl-screen-mirror` (a separate axis — output mirroring via
  wl-mirror; the `hypr-screen-mirror` variant is Hyprland-only, wrong for niri).
  Drop `color_picker`, `screen_recorder`. (Trade-off: `screen_recorder` uses GPU
  encoding — re-add it for heavy/long captures.)
- **Keybind viewer** — `keymap` (view + edit + layout render) is a strict
  superset of `keybind-cheatsheet`. Keep `keymap`; drop the cheatsheet.
- **Battery** (laptop-gated) — `battery-power-management` already does charge
  limit + power profiles + draw, making `battery-threshold` redundant (both
  write the charge limit → conflict). Keep `battery-power-management` +
  `battery-widget`; drop `battery-threshold`.
- **System / process / updates** — the **built-in** System-resources widget
  covers at-a-glance metrics, so the `system-monitor` plugin is redundant; add
  `procmon` for interactive process management. On Arch, `arch-updater`
  (pacman/AUR/flatpak) supersedes the distro-agnostic `system-updater`. Keep
  `procmon`, `arch-updater`, `cat` (cosmetic CPU load), `gamer-mode` (unique
  suspend-hogs action); drop `system-monitor`, `system-updater`.
- **Launcher** — the built-in launcher already evaluates math, so the
  `calculator` plugin is redundant; `file-search`, `shell-command` (`/sh`),
  `ssh-launcher` (`/ssh`) add providers the launcher lacks. Keep those three;
  drop `calculator`.

Remaining non-overlapping picks ship as-is: `niri-active-workspace`,
`niri-animations`, `niri-displays`, `sharednd`, `audio-switcher`,
`drive-health`, `eyecare`, `mini-docker`, `custom-shortcut`, `udiskie`, `todo`,
`wallpaper-switcher`.

## Laptop gating

There is no niri host profile and no battery concept in `.installer`. Rather
than invent one, an adapter-level `laptop` bool in `install-niri.jsonc` (default
= battery-present detection) gates the battery pair. It is independent of the
host-profile system.

## Sourcing and pinning

Register both default v5 sources — `noctalia-dev/official-plugins` and
`noctalia-dev/community-plugins`. Community-plugins is a **single repo**, so one
pinned commit covers all community picks and one the official picks: **two
refs total**, not one per plugin — reproducible installs at trivial maintenance,
bumped by editing two SHAs. Extends ADR 0090's pinned-Bitwarden precedent.

## Considered alternatives

- **A separate `noctalia-enriched` variant** — rejected: two presets to test and
  drift; per-plugin bools on the one preset already make it lean-recoverable.
- **`config-swap` for palette switching** — rejected: it swaps arbitrary files,
  is not palette-aware, and duplicates built-in theming.
- **Pin each plugin to its own ref** — rejected: community-plugins is one repo,
  so a single SHA suffices; ~20 refs would be needless churn.
- **Keep 0090's no-theming rule and ship no default palette** — rejected: a
  seeded default palette is the whole point of "enhance the default experience";
  the deviation is narrow (one key) and reversible.

## Consequences

- **v5 mechanism rework (done, verified).** ADR 0090's seeding wrote a
  `plugins.json {enabled, sourceUrl}` registry — a **v4** shape. v5 moved to
  `plugin.toml`, git **sources**, and a separate enable step; the seeding path
  was rewritten to vendor each plugin folder and enable it by canonical id in
  `[plugins].enabled`. Confirmed by a full VM install (see Status).
- **Trust surface.** v5 plugins are unsandboxed Luau run as the user. Seeding
  ~22 enabled-by-default into `/etc/skel` is a conscious expansion of what the
  preset trusts — acceptable because every source is pinned and operator-visible
  via the `install-niri.jsonc` bools.
- `install-niri.jsonc` grows a bool per plugin plus `laptop`; the Package
  Resolver reads the same file so install and report cannot drift (ADR 0021).
- The glossary's **Wayland Shell Companion** entry gains the enriched set, the
  seeded Rosé Pine default, and the `laptop` gate.
