# 20: Plasma keeps our colour scheme

**What to build:** Diagnose on a held VM what reasserts BreezeDark at login,
then fix the seed so the shipped scheme persists. Fixes F378.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Root cause noted in Comments
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base)

## Comments

Root cause: Noctalia leaves ColorScheme=BreezeDark while rewriting the
palette, so plasma-apply-colorscheme no-ops ('already set'). Reset clears the
key first (c06e17c); probe judges the palette (c73c15b). Also the skel
clock's char-split calendar plugin list (64c83e0).
