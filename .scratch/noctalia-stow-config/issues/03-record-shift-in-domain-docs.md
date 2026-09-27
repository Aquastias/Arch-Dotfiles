# 03 — Record the shift in the domain docs

**What to build:** a future maintainer reading the glossary and README
understands that the curated Noctalia config is now stow-owned (not skel-seeded)
and why the manual-stow path needs `--no-folding`. ADR 0094 already records the
decision; this ticket brings the living docs in line with it.

**Blocked by:** 02 — Curated Noctalia config ships as stow payload (the docs
describe the settled end state).

**Status:** done

- [x] `CONTEXT.md`'s **Wayland Shell Companion** entry updated: the curated
      config is stow-owned; only plugin vendoring is installer-seeded (was:
      installer-generated config into `/etc/skel`).
- [x] `README.md`'s manual-stow section notes `stow --no-folding` so a hand-run
      `stow .` keeps `~/.config/noctalia` a real dir (Noctalia writes its
      runtime `settings.toml`/state beside the symlinked config, never into the
      repo).
- [x] `CONTEXT.md` is a glossary only — no implementation detail leaks in.

## Comments

- 2026-09-27 doc sync: shipped in 63c1c48, 7cec055 (ADR 0094); stow delivery
  superseded by skel seeding (ADR 0095).
