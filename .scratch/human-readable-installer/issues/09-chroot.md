# 09: Chroot Configuration Modules

**What to build:** The chroot orchestrator and every Chroot Configuration
Module (Bootloader Adapters, impermanence, GPU, initcpio, Noctalia preset,
identity, …) follow the Readability Rules.

**Blocked by:** 05 — Pilot

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
