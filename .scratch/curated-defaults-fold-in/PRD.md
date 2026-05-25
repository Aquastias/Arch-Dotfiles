Status: done

# PRD: Fold Curated Defaults List into impermanence-common

## Problem Statement

The Curated Persist Defaults list exists twice:

- **Authoritative** in `lib/impermanence-common.sh` as `CURATED_FILES`
  and `CURATED_DIRS`. Consumed by `lib/chroot/impermanence.sh` (install)
  and `tools/impermanence.sh` (runtime).
- **Duplicated** in `lib/validation.sh` as `_VALIDATION_CURATED`, with
  a comment that reads "must mirror `lib/chroot/impermanence.sh`."

`_validation_persist_one` uses the duplicate to warn the operator when
a host-declared Persist Extension is already covered by a curated
default ("Redundant.").

The duplication is a hand-maintained invariant. Adding a path to the
curated list (e.g. `/etc/resolv.conf`) requires editing both files;
forgetting the second produces a silent validation gap, not a build
failure.

## Solution

Source `lib/impermanence-common.sh` from `lib/validation.sh`. Iterate
`CURATED_FILES + CURATED_DIRS` directly. Delete `_VALIDATION_CURATED`
and its inline comment.

## User Stories

1. As an impermanence-feature maintainer, I want to add a path to the
   Curated Persist Defaults list in one place, so that validation
   coverage cannot silently lag behind the install-time behavior.
2. As a contributor reading `lib/validation.sh`, I want the curated
   list to be obviously sourced from the canonical location, so that
   I don't wonder whether the two lists could legitimately differ.
3. As a contributor reading `lib/impermanence-common.sh`, I want all
   curated-list consumers to source the file, so that grep tells me
   every place that depends on the list.

## Implementation Decisions

- **Source `lib/impermanence-common.sh` from `lib/validation.sh`.**
  Today validation.sh has no impermanence-common dependency; adding
  it is a single `source` line plus a path resolution.
- **Iterate `CURATED_FILES + CURATED_DIRS` directly** in
  `_validation_persist_one`. The current `_VALIDATION_CURATED` array
  intermixes both kinds; the canonical lists separate them, but the
  validation check (path-prefix match) does not care about the
  distinction.
- **Delete `_VALIDATION_CURATED`** and its "must mirror" comment.
- **No behavior change.** The set of paths flagged as redundant is
  identical before and after — both lists currently contain the same
  entries.

## Testing Decisions

Good tests here assert observable behavior: which warnings are
emitted for which inputs.

- **Existing validation tests** — `tests/validation-impermanence.bats`
  (or its equivalent) already covers `_validation_persist_one`. The
  test that exercises "warns when path is in curated defaults" must
  continue to pass with no modification. If no such test exists, add
  one before the refactor as a regression guard.
- **Drift-prevention test** — a tiny test asserting that the curated
  arrays in `lib/impermanence-common.sh` are non-empty and that
  validation iterates them. This catches a future contributor who
  re-introduces a local copy in `validation.sh`.

Tests do not assert which array name validation iterates internally,
only that the right warnings come out for the right inputs.

## Out of Scope

- Changing the Curated Persist Defaults list itself.
- Refactoring the rest of `lib/validation.sh`. Only the persist
  validation block touches the duplicated list.
- The Install Config / Install State refactor (separate PRD:
  `config-modules-refactor`).
- The persist-verbs extraction (separate PRD:
  `persist-verbs-extraction`).

## Further Notes

Smallest of the three PRDs in this batch. Independent of the others —
can land first as a low-risk warmup, or last as a cleanup. Not
sequenced against `persist-verbs-extraction` even though both touch
`lib/impermanence-common.sh`; the changes don't overlap (this PRD
adds a sourcing relationship; the other adds new functions).
