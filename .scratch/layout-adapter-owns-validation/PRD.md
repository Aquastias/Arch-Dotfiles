Status: done

# PRD: Layout Adapter owns mode-specific validation

References: ADR 0014.

## Problem Statement

Mode-specific disk/topology validation lives in `lib/validation.sh`
as `_validation_single` and `_validation_multi`, dispatched
reflectively (`_validation_${INSTALL_MODE}`). Every other
mode-specific concern (planning, partitioning, pool creation, ESP
mount) is owned by the active Layout Adapter (`lib/layout-<mode>.sh`)
via the adapter pattern that ADR 0003 and ADR 0005 already
established for Bootloaders and Desktop Environments. Validation is
the odd one out — a Layout Module change forces a `validation.sh`
edit too. Adding a layout mode means touching two files; the
deletion test is weak (removing `layout-single.sh` leaves
`_validation_single` orphaned).

## Solution

Each Layout Adapter publishes `layout_validate` alongside
`layout_plan`, `layout_partition`, `layout_create_pools`,
`layout_mount_esp`. `validate_install_context` calls
`layout_validate` on the active adapter instead of dispatching
reflectively. The mode-specific validator bodies move into their
respective adapters. The reflective dispatcher and the
`_validation_${INSTALL_MODE}` mode-guard delete.

The active Layout Module is sourced from `03-install.sh` **before**
`validate_install_context` runs (today: after). Unknown
`INSTALL_MODE` fails at `source_module` time with a clear
file-not-found message instead of the dispatcher's
`declare -F` guard.

## User Stories

1. As the installer maintainer, I want adding a new layout mode to
   require only a new `lib/layout-<mode>.sh` with the full
   interface, so that I do not have to edit `validation.sh` in
   addition to the adapter.
2. As the installer maintainer, I want removing a layout mode to
   delete its validator along with the rest of its code, so that
   the deletion test holds and no orphaned validators linger.
3. As the installer maintainer, I want mode-specific validator
   tests to live next to the adapter they test, so that changing
   a layout adapter changes one test file.
4. As an operator running the install, I want an unknown
   `INSTALL_MODE` value to fail with "Cannot find
   lib/layout-foo.sh" instead of an internal "No validator for
   mode" error, so that the diagnostic points at the missing
   adapter directly.
5. As an operator running the install, I want bad disk paths or
   bad topology values to abort with the same error message and
   format as today, so that nothing observable changes from my
   perspective on the live CD.
6. As an installer-test author, I want to test mode-specific
   validation by invoking `layout_validate` on a sourced adapter,
   so that I do not have to set `INSTALL_MODE` and call
   `validate_install_context` end-to-end.
7. As a future engineer reading the Layout Module docstring in
   each adapter, I want `layout_validate` listed alongside the
   other published verbs, so that the full interface is visible in
   one place.

## Implementation Decisions

- **New verb on the Layout Module interface**: `layout_validate`.
  Pure check — no state writes, no `LAYOUT_*` population. Exits
  via `error` on first failure (matches current behaviour). Each
  adapter implements it; bodies are the existing
  `_validation_single` / `_validation_multi` content moved
  verbatim.
- **Dispatcher**: `validate_install_context` calls
  `layout_validate` directly. The `declare -F` guard against
  unknown `INSTALL_MODE` deletes — that case now fails earlier at
  `source_module` time.
- **Sourcing order**: `03-install.sh` sources
  `lib/layout-${INSTALL_MODE}.sh` between `detect_mode` and
  `validate_install_context` (today the source happens after
  validate). Sourcing has no side effects beyond defining
  functions, so loading the module on dry-run / validate-only
  paths is safe.
- **Pre-condition vs. post-condition naming**: `layout_validate`
  is the pre-condition (input check). Existing
  `_layout_verify_*_contract` helpers in `layout-common.sh` are
  post-conditions (output check). Names stay distinct — not
  renamed.
- **Untouched cross-cutting validators**: `_validation_system_fields`
  (hostname/locale/timezone), `_validation_impermanence`,
  `_validation_persist`, `_validation_preflight_programs` stay in
  `validation.sh` — they are not layout-specific.
- **CONTEXT.md** already updated to list `layout_validate` in the
  Layout Module interface and to note the source-before-validate
  ordering.

## Testing Decisions

- **What makes a good test**: exercise `layout_validate` through
  the published Layout Module interface — source the adapter,
  stage a fixture `install.jsonc`, set `INSTALL_MODE`, call
  `layout_validate`, assert exit status + stderr substring. Do
  not poke at internal disk-loop helpers.
- **Modules to test**: `lib/layout-single.sh` and
  `lib/layout-multi.sh`. Per-mode validator cases relocate from
  `tests/validation*.bats` to `tests/layout-single.bats` and
  `tests/layout-multi.bats` — co-located with the adapter they
  test.
- **Prior art**: the existing `tests/layout-single.bats` and
  `tests/layout-multi.bats` already test other Layout Module
  verbs (`layout_plan` etc.) via fixtures under
  `tests/fixtures/`. The new validator cases follow the same
  pattern — same fixture infrastructure, same stub strategy for
  `blockdev` / `lspci`.
- **Coverage to preserve**: every assertion currently made by
  `_validation_single` and `_validation_multi` must still fire
  in the new location. Disk-missing, bad-topology,
  no-disks-in-group, missing-group-disk — all keep the same
  error messages.
- **Out of band**: shellcheck must still pass; CI runs both bats
  suites.

## Out of Scope

- Pushing `install.jsonc` schema reads (`.disk`, `.os_pool.*`,
  `.storage_groups[]`) behind dedicated `layout_get_*`
  accessors. This is a separate Layout Module deepening tangled
  with the `install-config.sh` schema-table refactor; addressed
  separately if pursued.
- Changing the cross-cutting validators
  (`_validation_system_fields` and friends) in any way.
- Touching the Layout Module's published `LAYOUT_*` output
  globals.
- Phase-lifecycle guards on `layout_plan` / `layout_partition` /
  etc. (covered by ADR 0016 / its own PRD).

## Further Notes

- **Single commit** — all five edits land together
  (`lib/layout-single.sh`, `lib/layout-multi.sh`,
  `lib/validation.sh`, `03-install.sh`, tests). Splitting would
  leave the repo broken on intermediate commits (e.g. deleting
  `_validation_*` without adding `layout_validate` fails the
  install).
- **No external callers** of `_validation_single` /
  `_validation_multi` — confirmed via grep before this PRD was
  written. Safe to delete.
- **No ADR conflict** — this strengthens the adapter pattern
  established by ADR 0003 and ADR 0005 and is the basis of
  ADR 0014.
