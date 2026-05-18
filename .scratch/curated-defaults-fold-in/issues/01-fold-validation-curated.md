Status: ready-for-agent

# Fold `_VALIDATION_CURATED` into `impermanence-common.sh`

## Parent

`.scratch/curated-defaults-fold-in/PRD.md`

## What to build

`lib/validation.sh` sources `lib/impermanence-common.sh` and iterates
the canonical `CURATED_FILES` + `CURATED_DIRS` arrays directly in
`_validation_persist_one`. The duplicated `_VALIDATION_CURATED` array
and its "must mirror" comment are deleted.

The set of paths flagged as redundant must be identical before and
after — both arrays contain the same entries today.

## Acceptance criteria

- [ ] `lib/validation.sh` sources `lib/impermanence-common.sh`
- [ ] `_validation_persist_one` iterates `CURATED_FILES + CURATED_DIRS`
- [ ] `_VALIDATION_CURATED` array is removed
- [ ] "must mirror" comment is removed
- [ ] `tests/validation-impermanence.bats` passes unmodified
- [ ] A regression test exists asserting the curated-defaults warning
      fires for at least one path from each of `CURATED_FILES` and
      `CURATED_DIRS` (add one if absent)
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

None - can start immediately.
