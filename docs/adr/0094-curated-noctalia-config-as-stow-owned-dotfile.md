# The curated Noctalia config ships as a stow-owned dotfile

---
Status: accepted; its delivery mechanism (stow-at-install) is **superseded by
ADR 0095** — the curated config is now skel-seeded, not Runner-stowed; its
single-source-in-the-repo and config-*content* decisions stand. Partially
supersedes ADR 0093's "widget placement stays the user's" clause (scoped to the
placement clause only). Extends ADR 0090 (niri adapter + Noctalia preset) and
ADR 0012 (legacy top-level stow tree).
---

ADR 0090/0093 seeded a **minimal** glue `config.kdl` and an installer-**generated**
`config.toml` into `/etc/skel`, and deliberately placed **no** bar / Control-Center
widgets — the first-login enable one-shot activates plugins but never *places*
them ("widget placement stays the user's"). The operator now wants the **full
curated look** — bar order, widget placement, dock, lockscreen, palette, the
whole layout — shipped by default *and* editable/stowable like every other
dotfile in this repo. Those two goals collide with 0093's placement rule and
with `config.toml` being an installer heredoc.

## Decision

The curated config moves **out of installer heredocs into the dotfiles repo** as
ordinary stow payload:

- `.config/noctalia/config.toml` — the full curated look (single owner)
- `.config/niri/config.kdl` — the glue (autostart Noctalia, kitty, screenshot,
  spawn the enable-plugins one-shot)
- `.local/bin/noctalia-cycle-palette`, `.local/bin/noctalia-enable-plugins`

`niri.sh` no longer seeds any of these to `/etc/skel`. The Runner's existing
per-user `stow --no-folding` step (`lib/profiles/runner.sh`) delivers them during
install, so they are **shipped by the installer** *and* independently stowable
(`stow .`) from a **single source** — no skel/stow drift. Only plugin
**vendoring** — the one fetched, non-static step — stays installer-side, seeded
at a pinned ref into `/etc/skel/.local/share/noctalia/plugins/`; the stowed
one-shot enables whatever `[local]` plugins it finds at login, agnostic to who
vendored them.

`--no-folding` is load-bearing: it keeps `~/.config/noctalia` a **real** dir, so
Noctalia writes `settings.toml`/state *beside* the symlinked `config.toml` and
never back into the repo.

## Scope of the 0093 reversal

`config.toml` now carries **bar order + widget placement** — exactly what 0093's
placement clause excluded. The reversal is scoped to that clause and nothing
more. 0093's **host-bound** exclusions still hold, because a stowed dotfile must
stay portable across hardware: the lockscreen widget geometry keyed to an output
name (`@Virtual-1`, pixel positions, resolution) and the per-monitor / captured
wallpaper paths are **dropped**, not shipped. `[wallpaper.default]` points at the
packaged asset (`/usr/share/noctalia/assets/noctalia-wallpaper.png`) and Noctalia
regenerates host-bound state on first run. `auto_update = "none"` is kept (the
plugin set is pinned-vendored — background updates would defeat reproducibility).

## Riders (grounded in the same change)

- **Plugin set is the curated `enabled` list.** `bitwarden`, `mini-docker`, and
  `system-updater` are dropped — `system-updater` is redundant with `arch-updater`
  (0093) and is the only plugin whose deps reach into AUR (`cargo-update`) and an
  unresolved PackageKit name. `portctl`, `game-launcher`, `hotspot`, `bookmarks`,
  `llamanager` (pulls `ollama`), and `dns-switcher` join; all seven live at the
  already-pinned community ref. The laptop battery pair stays auto-gated.
- **Font.** `[shell] font_family = "Noto Sans"` for the UI; monospace/terminal
  roles (kitty, KDE fixed-width) use the Nerd font — the conventional split, since
  a proportional font breaks terminals and one mono font makes every UI look like
  one.
- **octopi** leaves `hosts/core` (every host) for `install-kde.jsonc`'s `aur`
  block — KDE-only, mirroring `qt6ct-kde`.

## Considered alternatives

- **Keep the skel seed and add a stowed copy** — rejected: two authoritative
  sources of the same file, guaranteed to drift (the exact problem ADR 0012 set
  out to kill).
- **Vendor the config as an installer-generated artifact, independent of the
  dotfiles** — rejected: the operator wants it editable *as a dotfile*, and on a
  personal repo the dotfiles **are** the config; an installer-owned copy re-opens
  the drift the move eliminates.
- **Use the ADR-0012 program config tree (`programs/*/configs/` + manifest)** —
  rejected for now: niri/Noctalia live under `extras/desktop/`, not `programs/`,
  and would be the first users of an untested manifest path; the legacy top-level
  stow tree already works and is what the repo runs today.

## Consequences

- The `install-niri.jsonc` bools, `packages/niri.sh` lists, and the stowed
  `config.toml` `enabled` list must be kept in step by hand — three files, one
  set. The vendored `[local]` folders remain the *operative* source of what
  actually enables at login (0093); the `config.toml` list is the declarative
  mirror.
- A niri+Noctalia install now **depends on this dotfiles repo being stowed** for
  its shell config (the Runner always does this). Bare niri (`niri_shell=none`)
  is unchanged.
- The glossary's **Wayland Shell Companion** entry gains: curated config is now
  stow-owned (not skel-seeded); only plugin vendoring is installer-seeded.
