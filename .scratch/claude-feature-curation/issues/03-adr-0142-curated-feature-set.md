# 03: ADR 0142 + CONTEXT note

**What to build:** The curated feature decisions are recorded so a future Claude
Code update that re-enables something is caught against a written rationale.
Author `docs/adr/0142-curated-claude-feature-set.md` documenting the keep/
disable choices and the installer-owned skill store, amending ADR 0133's
settings choices, with a disposition table (feature → keep/disable → why). Touch
`CONTEXT.md` / `docs/agents/*` only if the curation changes a term or a stated
consumer rule.

Disposition table to carry into the ADR:

| Feature | Decision | Why |
|---|---|---|
| Gmail / Calendar / Drive / Claude_Docs connectors | disable | 0 uses / 39 sessions |
| Remote Control | disable | unused; terminal workflow |
| Artifacts | disable | terminal workflow |
| Workflows | disable | none defined; 0 use |
| claude.ai skill/plugin sync | disable | keep skills repo-controlled |
| Telemetry / error reporting | disable | matches traffic opt-out |
| model | `claude-opus-5-5` | current recommended Opus (verified live + `/model`) |
| effortLevel | `medium` | Opus 5.5 native default |
| Matt Pocock skills (all) | keep + installer-owned | full workflow; reproducible |
| Grep / Glob | keep | unused but built-in, free |
| checkpointing / auto-compact / thinking / bg agents | keep | in active use |

**Blocked by:** 01, 02 (records the set as actually implemented).

**Status:** ready-for-agent

- [ ] `docs/adr/0142-curated-claude-feature-set.md` exists, follows the repo ADR
      format, and amends ADR 0133
- [ ] The disposition table is included and matches the shipped `settings.json`
      + skill bootstrap
- [ ] Cross-links (ADR 0133/0134, the skill CLI) resolve
- [ ] Any CONTEXT/doc term touched by the curation is updated; otherwise noted
      as no-change
