# 03 — Pairwise reducer (pure covering array)

Status: ready-for-agent
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

- [ ] Every valid value-pair from the input axes appears in at least one emitted
      row.
- [ ] No constraint-excluded pair appears in any row.
- [ ] Identical input + seed produces byte-identical output (determinism).
- [ ] Handles single-value axes and heavily-constrained axes without emitting
      impossible rows.
- [ ] Unit tests assert pair-coverage, exclusion-respect, and determinism
      (minimality is NOT asserted — implementation detail).

## Blocked by

None - can start immediately.
