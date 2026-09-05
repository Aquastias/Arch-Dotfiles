# Catppuccin Mocha Sapphire default, seeded offline

---
Status: accepted. **Supersedes the default *palette* of ADR 0101** (Catppuccin
Mocha Lavender) — the community-palette *mechanism* it chose is unchanged; only
the accent moves. **Resolves ADR 0101's "first boot needs network" consequence**
by seeding the palette's cache JSON into `/etc/skel`.
---

The default Noctalia palette changes from **Catppuccin Mocha Lavender** to
**Catppuccin Mocha Sapphire** — the community palette whose dark `mPrimary` is
`#74c7ec` (sapphire), the accent Noctalia paints across the shell and pushes to
apps via its templates. `builtin` stays `Catppuccin` and `mode` stays `dark`, so
the family and dark default are unchanged.

ADR 0101 recorded a real cost: community palettes are fetched from
`api.noctalia.dev` and cached, so a fresh **offline** first boot showed the
builtin fallback (Catppuccin Mocha, builtin **mauve** accent `#cba6f7`) until it
could fetch — a visible builtin→community cross-fade, and a hard network
dependency for the intended look. That is unacceptable for VM / offline installs.

## Decision

**Seed the palette's cache JSON offline.** Noctalia resolves a community palette
by reading `$XDG_STATE_HOME/noctalia/community-palettes/<url-encoded-name>.json`
before it ever touches the network (verified against Noctalia source and the
live cache path on the VM: `Catppuccin%20Mocha%20Sapphire.json`, the space
URL-encoded as `%20`). `noctalia-preset.sh` seeds that exact file into
`/etc/skel`, so first boot resolves Sapphire with **zero network** — no
cross-fade, no `api.noctalia.dev` dependency. The JSON is **vendored** (embedded
in the preset), pinning the palette like the plugin set is pinned (ADR 0093); it
is seed-only (never stowed — Noctalia rewrites the cache, which through a stow
symlink would dirty the repo, ADR 0104).

If the cache is ever absent, the resolver still falls back to the builtin named
by `builtin = "Catppuccin"` (Mocha, mauve) — so the box is themed regardless,
just not sapphire until the cache lands.

## Considered options

- **Switch the default to a builtin palette** (`source = "builtin"`) for
  byte-for-byte offline determinism — rejected: the builtin Catppuccin exposes
  **no accent selector** and its dark accent is mauve `#cba6f7`, not sapphire.
  It cannot express the chosen accent. (This mirrors ADR 0101's rejection of the
  builtin for the same reason.)
- **Fetch the palette JSON at install time** from `api.noctalia.dev` (as plugins
  are fetched from git) — workable, but adds an install-time network dependency
  and non-determinism. Vendoring the JSON is fully offline and reproducible.
- **Keep ADR 0101's Lavender default** — rejected: the operator chose sapphire.

## Consequences

- **The default look is deterministic and offline** on any box, VM or hardware —
  the ADR 0101 network dependency for the default palette is gone.
- **The palette lives in three places** (the `config.toml` selector, the seeded
  cache JSON, and the ADR 0108 boot-race snapshot); changing the default means
  updating all three. Documented cost of full offline + no-flash theming.
- The palette-cycle tile (ADR 0093) still cycles the *builtin* palettes and does
  not return to this community default — cycling stays an explicit "explore
  builtins" action.
- `noctalia-stow.bats` asserts the Sapphire selector in `config.toml` and the
  seeded cache JSON in the preset.
