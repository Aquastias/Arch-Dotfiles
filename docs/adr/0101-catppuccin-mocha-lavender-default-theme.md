# Catppuccin Mocha (lavender) as the default Noctalia theme

---
Status: accepted. **Amends ADR 0093**, which set Rosé Pine as the default
Noctalia palette — the enriched-plugin decision there is unchanged; only the
default palette is superseded.
---

The default Noctalia look changes from Rosé Pine to **Catppuccin Mocha with a
lavender accent**, via the community palette **"Catppuccin Mocha Lavender"**
(`source = "community"` in the curated `config.toml`, `mode = "dark"`). Its
`mPrimary` is `#b4befe` — Catppuccin's lavender — which is the accent Noctalia
paints across the shell and pushes to apps through its templates. `builtin` is
also set to `Catppuccin` so a builtin fallback stays in the same family.

Because `config.toml` is the **shared** shell config (ADR 0097, byte-identical
on niri and Hyprland), this one change themes the shell on both compositors.
Window-border colors differ by compositor plumbing: niri's are palette-driven by
Noctalia, but **Hyprland's are hardcoded in `hyprland.conf`**, so those are set
directly to the same accent — active `lavender → pink` (the palette's primary +
secondary `#b4befe`/`#f5c2e7`), inactive a muted overlay `#6c7086` — keeping the
two compositors visually matched.

## Considered options

- **Builtin `Catppuccin`** — rejected: the builtin exposes no accent selector,
  so a lavender accent is not guaranteed.
- **A seeded custom palette** (offline) — built first, then rejected by the
  operator in favour of the maintained community palette; kept in mind should
  offline-first ever matter.
- **Mauve accent** (`Catppuccin Mocha Mauve-Lavender`) — the first pick this
  session, switched to lavender before it settled.

## Consequences

- **First boot needs network.** Community palettes are fetched from
  api.noctalia.dev and cached locally, so a fresh, offline first login shows a
  fallback palette until it can fetch — unlike the otherwise offline-seeded
  curated config. Accepted; it mirrors the plugin-enable one-shot's existing
  first-boot network need (ADR 0093).
- **Hyprland border colors are hardcoded to the accent**, so a later palette
  change means editing `hyprland.conf` too (niri needs no such edit). Acceptable
  until/unless Hyprland borders are wired to Noctalia's hyprland template.
- The palette-cycle tile (ADR 0093) still cycles the *builtin* palettes; it does
  not return to this community default, so cycling is an explicit "explore
  builtins" action.
- The glossary's **Wayland Shell Companion** entry updates its named default.
