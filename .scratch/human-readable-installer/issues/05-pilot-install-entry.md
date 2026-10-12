# 05: Pilot: install entry script + direct libs

**What to build:** The install entry script opens with a `main()` reading
as the install's table of contents, and the libs it sources directly follow
every Readability Rule. `ARCHITECTURE.md` links to the `main()` instead
of restating the flow. Ends with an owner style review; the readability
doc is adjusted to what's agreed before 06–21 start.

**Blocked by:** 02 — Prefix Map; 03 — Commons path helpers

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
- [x] Full VM install green at ticket close
- [x] `main()` outline at top; `ARCHITECTURE.md` links to it
- [x] Owner style review done; doc updated with outcomes

## Comments

- Pilot scoped to 03-install.sh + lib/config/lifecycle.sh + lib/finalize.sh
  (03-install sources 24 libs; all of them would swallow tickets 06-14).
  Summary output verified byte-identical across all 360 matrix cells.
  Awaiting owner style review; VM install not run yet.
- 2026-10-12: closed. Owner review outcome: "everything is fine code wise" —
  no doc changes needed. Full VM install green (zfs-single-plain, 2026-10-11)
  covers 03-install.sh, lifecycle.sh and finalize.sh.
