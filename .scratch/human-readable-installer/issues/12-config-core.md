# 12: Config core

**What to build:** Config state, Config Store, Layer Resolver, validation,
profile loading, seed, and Install Config accessors follow the Readability
Rules.

**Blocked by:** 05 — Pilot

**Status:** ready-for-agent

- [ ] Renames per the Prefix Map applied to every definition here and
      every caller repo-wide (incl. bats/helpers); frozen interface untouched
- [ ] Locals/globals follow the Readability Rules; no non-acronym
      abbreviations left
- [ ] Replace-tier tools gone; `sed` only in-place; consecutive `jq` reads
      merged where it stays short
- [ ] Files ≤ 500 lines, touched functions ≤ ~50 lines / ≤ 3 nesting
- [ ] Lib headers carry `Used by:`
- [ ] Baseline entries for this area deleted (lint fails if any linger)
- [ ] Separate rename / tools / split commits; shellcheck, bats, `audit.sh`,
      Readability Lint green on each
- [ ] Any `CONTEXT.md` term touched renamed first; ADRs untouched; bugs found
      filed as separate tickets
- [ ] Full VM install green at ticket close
