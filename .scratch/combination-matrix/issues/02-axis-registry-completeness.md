# 02 — Axis registry + completeness assertion

Status: done
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

- [x] A field present in `_MENU_FIELDS` but absent from the registry makes the
      assertion fail, naming the offending path.
- [x] A registry entry whose path is not in `_MENU_FIELDS` also fails.
- [x] A fully-covered registry passes; role and weight lookups return the
      registered values.
- [x] `matrix.sh gen` invokes the assertion and aborts on any gap.
- [x] Unit tests cover the pass, missing-field, and stale-entry cases.

## Blocked by

- `.scratch/combination-matrix/issues/01-tracer-bullet-spine.md`

## Comments

**Done 2026-07-08 (TDD, LOCAL/UNPUSHED).** `lib/matrix/registry.sh`:
`_MATRIX_AXIS_REGISTRY` classifies all 26 `_MENU_FIELDS` paths into a role
(storage-cluster / pairwise-affecting / scalar-sweep / inert) + light/heavy
weight. `matrix_registry_assert` diffs registry↔`_MENU_FIELDS` via `comm`:
`unclassified axis <path>` on a menu field with no entry, `stale registry entry
<path>` on the inverse. `matrix_gen_cells` now calls it first → gen aborts on
any drift. `matrix_axis_role`/`matrix_axis_weight` lookups. 6 registry bats,
matrix suite 12/12.

**Roles (per PRD):** storage-cluster = filesystem, options.encryption,
options.impermanence.enabled. pairwise-affecting = kernel, bootloader,
ssh.enabled, desktop, gpu, multilib. scalar-sweep = esp_size. inert = identity
(hostname/locale/timezone/keymap), age_key_url, sysctl, mirror_countries,
packages.extra, system_programs, security/backup toggles, users. heavy weight =
desktop, gpu, packages.extra, system_programs, users. The registry is the single
adjustable point; slices 04/05 refine against real generator behaviour. (Note:
topology / disk-mode / per-group data-pool axes are NOT `_MENU_FIELDS` entries —
they come from the layout/data-pools editor and are added as derived axes in
slice 04, so they're out of this completeness assertion's scope.)
