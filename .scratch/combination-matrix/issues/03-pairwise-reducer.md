# 03 — Pairwise reducer (pure covering array)

Status: done
Type: AFK

## Parent

`.scratch/combination-matrix/PRD.md`

## What to build

A standalone, menu-agnostic **pairwise reducer**: given a set of axes (each with
its allowed values) and a set of exclusion constraints, emit a deterministic
2-wise covering array — a list of assignments in which every valid value-pair
across every axis-pair co-occurs in at least one row, and no constraint-excluded
pair ever appears. The draw is seeded so identical input yields identical output.

Pure function, no dependency on the menu or VM layers — it is fed axes and
returns rows.

## Acceptance criteria

- [x] Every valid value-pair from the input axes appears in at least one emitted
      row.
- [x] No constraint-excluded pair appears in any row.
- [x] Identical input + seed produces byte-identical output (determinism).
- [x] Handles single-value axes and heavily-constrained axes without emitting
      impossible rows.
- [x] Unit tests assert pair-coverage, exclusion-respect, and determinism
      (minimality is NOT asserted — implementation detail).

## Blocked by

None - can start immediately.

## Comments

**Done 2026-07-08 (TDD, LOCAL/UNPUSHED).** `lib/matrix/pairwise.sh` —
`matrix_pairwise <axes_json> <constraints_json> [seed]` → JSON-lines rows, keys
in axis order. Menu-agnostic, pure bash after a jq parse.

**Algorithm:** greedy pair coverage. Enumerate valid pairs (a pair is excluded
iff a constraint whose keys ⊆ the pair's two axes matches — so 1-key constraints
forbid a value outright, 2-key forbid a combo). Loop: seed a row from the
deterministically-first uncovered pair (`sort -t,` numeric), complete it by a
coverage-maximising forward pass; if constraints block the forward pass, fall
back to a backtracking search — so a completable pair is never dropped and a
genuinely impossible pair emits no row (just leaves the cover). Determinism: seed
rotates each axis's value try-order; sorted pair pick + axis-order row emit ⇒
byte-identical output for identical input+seed. Minimality intentionally NOT
pursued (AC excludes it).

5 bats (2-axis full, 3-axis coverage, exclusion-respect, determinism,
single-value+heavy-constraint no-impossible-rows). Matrix suite 17/17,
shellcheck clean. Constraint input format `[{"fs":"ext4","topology":"mirror"}]`
is what the slice-04 generator will feed from the menu's fs↔topology rules.
