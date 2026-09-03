# Catppuccin Mocha (mauve) as the default Noctalia theme

---
Status: accepted. **Amends ADR 0093**, which set Rosé Pine as the default
Noctalia palette — the enriched-plugin decision there is unchanged; only the
default palette is superseded.
---

The default Noctalia look changes from Rosé Pine to **Catppuccin Mocha with a
mauve accent**, via the community palette **"Catppuccin Mocha Mauve-Lavender"**
(`source = "community"` in the curated `config.toml`, `mode = "dark"`). Its
`mPrimary` is `#cba6f7` — Catppuccin's mauve — which is the accent Noctalia
paints across the shell and pushes to apps through its templates. There is no
pure "Catppuccin Mocha Mauve" in the community palette repo; Mauve-Lavender is
the mauve-accented Mocha (mauve primary, lavender secondary). `builtin` is also
set to `Catppuccin` so a builtin fallback still lands on the same family.

## Considered options

- **Builtin `Catppuccin`** — rejected: the builtin exposes no accent selector,
  so a mauve accent is not guaranteed.
- **A seeded custom palette** (Mocha base + mauve `mPrimary`, offline) — built
  first, then rejected by the operator in favour of the maintained community
  palette; the custom route is kept in mind should offline-first ever matter.

## Consequences

- **First boot needs network.** Community palettes are fetched from
  api.noctalia.dev and cached locally, so a fresh, offline first login shows a
  fallback palette until it can fetch — unlike the otherwise offline-seeded
  curated config. Accepted; it mirrors the plugin-enable one-shot's existing
  first-boot network need (ADR 0093).
- The palette-cycle tile (ADR 0093) still cycles the *builtin* palettes; it does
  not return to this community default, so cycling is an explicit "explore
  builtins" action.
- The glossary's **Wayland Shell Companion** entry updates its named default.
