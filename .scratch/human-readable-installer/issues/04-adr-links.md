# 04: ADR links in docs

**What to build:** Every `ADR NNNN` mention in tracked Markdown
becomes a relative link to its ADR file, so readers jump straight to the
reasoning. Excluded: `.scratch/`, vendored `.agents/skills/`; `docs/adr/`
cross-links included. Code comments keep plain `(ADR NNNN)`. The lint's
doc rule enforces it.

**Blocked by:** 01 — Readability Lint

**Status:** ready-for-agent

- [ ] All in-scope mentions linked, links resolve to existing files
- [ ] Lint rule + fixtures (unlinked doc mention caught; `.scratch/` and
      code comments allowed); suite green
- [ ] No ADR body text changed beyond link markup
