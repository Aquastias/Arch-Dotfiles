# 16: Rename guided controller

**What to build:** The split controller files follow every Readability Rule:
`_ctl_*` and its abbreviations (`pw`, `enc`, `nav`, `biglist`, …) become
readable names per the Prefix Map; long functions split.

**Blocked by:** 15 — Split guided controller

**Status:** done

- [x] Renames per the Prefix Map applied to every definition here and
      every caller repo-wide (incl. bats/helpers); frozen interface untouched
- [x] Locals/globals follow the Readability Rules; no non-acronym
      abbreviations left
- [x] Replace-tier tools gone; `sed` only in-place; consecutive `jq` reads
      merged where it stays short
- [x] Files ≤ 500 lines, touched functions ≤ ~50 lines / ≤ 3 nesting
- [x] Lib headers carry `Used by:`
- [x] Baseline entries for this area deleted (lint fails if any linger)
- [x] Separate rename / tools / split commits; shellcheck, bats, `audit.sh`,
      Readability Lint green on each
- [x] Any `CONTEXT.md` term touched renamed first; ADRs untouched; bugs found
      filed as separate tickets
- [x] Guided-flow run green (single/guided, --verify-boot, 2026-10-12)
