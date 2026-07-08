# 02 — Axis registry + completeness assertion

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/combination-matrix/PRD.md`

## What to build

The **stay-in-sync enforcer**. A pure module holding an axis registry that maps
every `_MENU_FIELDS` path to a role — `storage-cluster` / `scalar-sweep` /
`pairwise-affecting` / `inert` — plus a light/heavy weight. It exposes the
role/weight for a path and asserts the registry covers `_MENU_FIELDS` *exactly*:
a menu field with no registry entry hard-fails the generator with
`unclassified axis <path>`, and a registry entry for a non-existent field also
fails.

This is what turns "a new menu option should update the tests" into "you cannot
run the generator until you classify the new option."

## Acceptance criteria

- [ ] A field present in `_MENU_FIELDS` but absent from the registry makes the
      assertion fail, naming the offending path.
- [ ] A registry entry whose path is not in `_MENU_FIELDS` also fails.
- [ ] A fully-covered registry passes; role and weight lookups return the
      registered values.
- [ ] `matrix.sh gen` invokes the assertion and aborts on any gap.
- [ ] Unit tests cover the pass, missing-field, and stale-entry cases.

## Blocked by

- `.scratch/combination-matrix/issues/01-tracer-bullet-spine.md`
