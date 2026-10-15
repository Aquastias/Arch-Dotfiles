# 03: Raw config read lint with a ratcheting baseline

**What to build:** a lint (beside the Readability Lint, same ratchet idiom)
that fails on a raw jq read of an Install Config path with an inline
`// <default>` outside the Install Config Reader. Today's reads are recorded
in a baseline that may only shrink: a new raw read fails; removing one
without updating the baseline fails too. Decisions: candidate #1, Q18.

**Blocked by:** 01

**Status:** done

- [x] New raw read outside the reader fails the lint
- [x] Baseline lists today's reads; stale entries fail
- [x] Wired into the always-on test run
- [x] Agent doc says: read through the reader (bind for JSON)

## Comments

2026-10-15: tests/raw-config-reads.sh + .bats (8 tests; headline gates the
repo in the always-on run). Rule narrowed to literal defaults (string,
number, bool) — `// empty|null|[]|{}` are coalescing in state edits and
layer merges, not Install Defaults (first draft flagged 251, mostly those).
Baseline: 83 reads in 28 files. Doc: docs/agents/readability.md "Config
reads".
