# Ship the curated Noctalia+niri config as a stow-owned dotfile

Status: ready-for-agent

Anchoring decision: **ADR 0094** (curated Noctalia config as a stow-owned
dotfile). Extends ADR 0090 (niri adapter + Noctalia preset), ADR 0093 (enriched
plugin preset — partially superseded on the widget-placement clause), ADR 0012
(legacy top-level stow tree).

## Problem Statement

The operator has a fully curated Noctalia work desktop (bar order, widget
placement, dock, lockscreen, palette, plugin set) captured from a live session.
Today the installer *generates* a **minimal** Noctalia/niri config into
`/etc/skel` and, per ADR 0093, deliberately **does not place widgets** — the
first-login one-shot only *enables* plugins. So a fresh install does not
reproduce the curated look, and the config the operator actually wants is trapped
inside installer heredocs: it cannot be edited, versioned, or `stow`-ed like
every other dotfile in this repo. The operator wants the curated look shipped by
default **and** to live outside `.installer/` as ordinary stow payload — from a
single source, with no second copy to drift.

## Solution

Move the curated Noctalia/niri config **out of installer heredocs into the
dotfiles repo** as ordinary top-level stow payload. The installer keeps only the
one genuinely-fetched step — plugin **vendoring** at a pinned ref — and stops
seeding config/scripts to `/etc/skel`. The Runner's existing per-user
`stow --no-folding` step delivers the payload during install, so the config is
**shipped by the installer** and independently **stowable** (`stow .`) from one
source. The curated config is cleaned of host-bound state (per 0093/0094) so it
stays portable across hardware, the plugin set is corrected to the operator's
list, and `octopi` moves to KDE-only.

## User Stories

1. As the operator, I want the full curated Noctalia look (bar order, widget
   placement, dock, lockscreen, palette) to apply on first login, so that a fresh
   install reproduces my prepared desktop without manual layout work.
2. As the operator, I want `~/.config/noctalia/config.toml` to be a normal stowed
   dotfile, so that I can edit and version it like every other config in the repo.
3. As the operator, I want `~/.config/niri/config.kdl` to be a stowed dotfile, so
   that the niri glue (Noctalia autostart, kitty, screenshot) is editable in-repo.
4. As the operator, I want the palette-cycle and plugin-enable scripts to be
   stowed dotfiles, so that a box provisioned by plain `git clone + stow .` (no
   installer) still auto-enables plugins and has a working palette tile.
5. As the operator, I want a single source of truth for the config, so that the
   installer and the stow tree can never ship two copies that drift apart.
6. As the operator, I want the installer to still deliver the config during a
   full install, so that I do not have to run stow by hand after provisioning.
7. As the operator, I want the installer to keep vendoring the plugin folders at
   a pinned ref, so that plugin activation still works offline and reproducibly.
8. As the operator, I want host-bound surfaces (lockscreen widget geometry keyed
   to `@Virtual-1`, per-monitor and captured wallpaper paths) excluded from the
   stowed config, so that it survives a move from the capture VM to real hardware.
9. As the operator, I want the wallpaper to default to the packaged Noctalia asset
   (`/usr/share/noctalia/assets/noctalia-wallpaper.png`), so that a fresh box has
   a deterministic wallpaper instead of a dead bing path.
10. As the operator, I want the UI font set once to `Noto Sans` at
    `[shell] font_family`, so that the whole shell UI uses one proportional font
    without a per-bar override.
11. As the operator, I want terminal/fixed-width roles to keep using the Nerd
    monospace font, so that terminals and the Powerlevel10k prompt render
    correctly (a proportional UI font would break column alignment).
12. As the operator, I want the enabled plugin set to be exactly my curated list,
    so that only the plugins I chose are installed and activated.
13. As the operator, I want `bitwarden` removed from the default set, so that the
    Bitwarden CLI/plugin and its nodejs-LTS swap are no longer pulled in.
14. As the operator, I want `mini-docker` removed from the default set, so that
    `docker` is not installed as a side effect of the shell preset.
15. As the operator, I want `system-updater` dropped, so that I do not ship a
    plugin redundant with `arch-updater` whose deps reach into the AUR and an
    unresolved PackageKit name.
16. As the operator, I want `portctl`, `game-launcher`, `hotspot`, `bookmarks`,
    `llamanager`, and `dns-switcher` added, so that the installed set matches my
    curated bar.
17. As the operator, I want `llamanager` to pull `ollama`, so that "make sure
    ollama installs" is satisfied by the plugin's own declared dependency.
18. As the operator, I want the new plugins' official-repo tool deps (`iw`,
    `bind`, `xdg-utils`, `ollama`) installed only when the plugin is enabled, so
    that the dependency footprint tracks the enabled set.
19. As the operator, I want the laptop battery pair to stay auto-gated by battery
    presence, so that my desktop host does not get battery widgets it cannot use.
20. As the operator, I want the orphan widget stanzas (`phone-connect`,
    `ip-monitor`, `ocr`) whose plugins are not enabled stripped from the config,
    so that the shipped config has no dead references.
21. As the operator, I want the `[bar.default] font_family` override removed in
    favour of the single `[shell]` setting, so that there is one font knob.
22. As the operator, I want `auto_update = "none"` kept in the stowed config, so
    that the pinned-vendored plugin set is not silently updated in the background.
23. As the operator, I want `octopi` removed from the shared host base, so that a
    niri-only or laptop host never installs it.
24. As the operator, I want `octopi` installed only when KDE is selected, so that
    it ships alongside KDE like the other KDE-tied AUR tools.
25. As the operator, I want the niri adapter to no longer seed config/scripts to
    `/etc/skel`, so that stow is the sole owner and there is no skel/stow conflict.
26. As the operator, I want a test that fails if the stowed config's enabled list
    drifts from the installer's vendored set, so that the "three files, one set"
    invariant is enforced mechanically.
27. As a future maintainer, I want ADR 0094 and the updated glossary entry to
    explain why the curated config is stow-owned (reversing 0093's placement
    clause), so that the contradiction with 0093 is recorded, not surprising.
28. As the operator, I want bare niri (`niri_shell=none`) unchanged, so that the
    core-only path still seeds nothing.

## Implementation Decisions

- **New stow payload at the repo root** (delivered by the Runner's existing
  `stow --no-folding` step; independently `stow .`-able):
  - `.config/noctalia/config.toml` — the full curated look, single owner.
  - `.config/niri/config.kdl` — glue: autostart `noctalia --daemon`, bind kitty +
    native screenshot, spawn the plugin-enable one-shot.
  - `.local/bin/noctalia-cycle-palette`, `.local/bin/noctalia-enable-plugins` —
    the palette cycler and the first-login one-shot, verbatim from today's
    installer heredocs.
- **`config.toml` contents:** `[theme]` `source="builtin"`, `builtin="Rosé Pine"`,
  `mode="dark"`, `community_palette="Oxocarbon"`, `wallpaper_scheme="m3-content"`;
  `[shell] font_family="Noto Sans"` + `app_icon_colorize=true`;
  `[audio] enable_overdrive`; `[dock]`; `[nightlight]`;
  `[wallpaper.default] path="/usr/share/noctalia/assets/noctalia-wallpaper.png"`;
  `[plugins] auto_update="none"`, `enabled=[the curated ids]`; the curated
  `[bar.*]`/`[widget.*]`/`[lockscreen_widgets]` (widget list only) blocks; the
  `[plugin_settings."yocraft/custom-shortcut"]` tile block.
- **`config.toml` exclusions (kept out for portability):** bing
  `[wallpaper.last]` / `[wallpaper.monitors.Virtual-1]`; the `@Virtual-1`
  lockscreen widget geometry block; the orphan widget stanzas
  (`icefish/phone-connect`, `3ri4ng0ld/ip-monitor`, `fel/ocr`); the
  `[bar.default] font_family` override.
- **Plugin set (source of truth = the curated enabled list):** drop `bitwarden`,
  `mini-docker`, `system-updater`; add `portctl`, `game-launcher`, `hotspot`,
  `bookmarks`, `llamanager`, `dns-switcher`. Laptop battery pair stays
  auto-gated and is *not* in the static enabled list (it is enabled at login by
  the one-shot on battery hardware).
- **`extras/desktop/niri/niri.sh`:** remove the `config.kdl` and `config.toml`
  heredoc seeding and the palette-cycler / plugin-enabler seeding (they move to
  stow). Remove **all** Bitwarden logic (the `bitwarden` bool, the pinned-ref
  constants, the plugin section, and the plain-`nodejs` → `nodejs-lts-jod` swap).
  Keep: core, session curation, preset packages, cava/cliphist toggles, plugin
  vendoring to `/etc/skel/.local/share/noctalia/plugins`, tool-dep install,
  laptop gating.
- **`extras/desktop/niri/install-niri.jsonc`:** drop the `bitwarden` and
  `mini-docker` bools; add bools for the six new plugins.
- **`lib/packages/niri.sh`:** update `noctalia_community_plugins` to the new set;
  drop `noctalia_bitwarden_packages`; extend `noctalia_plugin_deps`
  (`game-launcher`→`xdg-utils`, `hotspot`→`iw`, `llamanager`→`ollama`,
  `dns-switcher`→`bind`); drop the `mini-docker`→`docker` case.
- **octopi:** remove from `hosts/core/profile.jsonc` `packages.aur.misc`; add to
  `extras/desktop/kde/install-kde.jsonc` `aur` (e.g. a `system` category), so it
  installs iff KDE is selected — mirroring `qt6ct-kde`.
- **Docs:** ADR 0094 already written. Update `CONTEXT.md`'s **Wayland Shell
  Companion** glossary entry: curated config is now stow-owned (not skel-seeded);
  only plugin vendoring is installer-seeded. Add a `--no-folding` note to the
  manual-stow section of `README.md`.
- **Drift invariant:** the `config.toml` `enabled` list, the `install-niri.jsonc`
  bools, and `noctalia_community_plugins` name the same set. The vendored
  `[local]` folders remain the operative source of what enables at login (0093);
  the `config.toml` list is the declarative mirror, guarded by a test.

## Testing Decisions

Good tests here assert **external behaviour at the highest existing seam**: what
packages the adapter installs, what folders it vendors, what the shipped config
*contains* — never internal function names or intermediate variables. Prior art
is `tests/extras/niri-adapter.bats` (adapter-as-subprocess with pacman/git/
systemctl stubs, asserting `PACMAN_LOG`/`GIT_LOG`/seed-dir contents) and
`tests/extras/kde-adapter.bats` / `tests/profiles/profiles-aur.bats` for
adapter/AUR resolution.

- **Seam A — reuse `tests/extras/niri-adapter.bats`** (the adapter subprocess
  seam). The adapter slims down, so this file changes shape:
  - Keep: core packages, `seatd`, session curation, no-DM, preset packages,
    cava/cliphist toggles, plugin **vendoring** to skel `.local/share` + tool-dep
    install + pinned community ref, laptop gating, dropped-plugins-never-vendored,
    all-off lean recovery.
  - Remove: every assertion that the adapter seeds `config.kdl`, `config.toml`
    (palette/look/enabled/tile), `noctalia-cycle-palette`, or
    `noctalia-enable-plugins`; remove all Bitwarden tests.
  - Add: vendoring of the six new plugins and their new deps (`iw`, `ollama`,
    `bind`, `xdg-utils`); assert `bitwarden`, `mini-docker`, and `system-updater`
    are never vendored and their unique deps (`docker`, `bitwarden-cli`) never
    installed.
- **Seam B — new `tests/config/noctalia-stow.bats`** over the committed stow
  payload. Asserts required keys/values in `config.toml` (`Rosé Pine`,
  `font_family = "Noto Sans"`, the packaged wallpaper path, `auto_update = "none"`,
  the enabled ids), the `config.kdl` glue (Noctalia autostart + enable-plugins
  spawn), and the two scripts present + shaped (`msg color-scheme-set`, `[local]`,
  the run-once guard). Asserts the **forbidden** content absent (`Virtual-1`, bing
  paths, `lockscreen_widgets` geometry, the three orphan widgets, `[bar.default]
  font_family`). Includes the **drift guard**: the `enabled` list equals
  `noctalia_community_plugins` (sourced from `lib/packages/niri.sh`) minus the
  laptop pair.
- **Seam C — reuse `tests/extras/kde-adapter.bats` + `tests/profiles/
  profiles-aur.bats`** for octopi: it resolves under KDE `aur`, and is absent from
  the core `aur` (a niri-only host never pulls it).

## Out of Scope

- Migrating Noctalia/niri to the ADR-0012 program config tree
  (`programs/*/configs/` + manifest). Rejected in ADR 0094 for now; legacy
  top-level stow is used.
- Any change to bare niri (`niri_shell=none`), which continues to seed nothing.
- Re-theming, new palettes, or changes to the palette-cycle mechanism itself.
- Whether `octopi` "belongs" to KDE conceptually — the operator's decision to make
  it KDE-only stands regardless of prior curation notes.
- Bumping the pinned plugin refs (all six new plugins already exist at the current
  community ref `caed21a`).

## Further Notes

- `--no-folding` is load-bearing: it keeps `~/.config/noctalia` a real directory so
  Noctalia writes `settings.toml`/state beside the symlinked `config.toml`, never
  into the repo. The Runner already uses it (`lib/profiles/runner.sh`); only the
  manual `stow .` in `README.md` needs the note.
- The plugin-enable one-shot is agnostic to who vendored the `[local]` folders, so
  stowing it (rather than skel-seeding it) is safe and makes the pure-`stow` path
  whole.
- Dependency-name mapping for the new plugins was verified against each
  `plugin.toml` at ref `caed21a`: `portctl`→`ss` (iproute2, base),
  `game-launcher`→`cc`/`xdg-utils`, `hotspot`→`iw`/`nmcli`/`ip`,
  `bookmarks`→`nohup` (coreutils, base), `llamanager`→`ollama`,
  `dns-switcher`→`dig`/`nslookup` (bind)/`networkmanager`. Only `iw`, `ollama`,
  `bind`, and `xdg-utils` are genuinely new official-repo packages.
