# ADR 0014: Layout Adapter owns mode-specific validation

## Status
Accepted

## Context
`validate_install_context` (`lib/validation.sh`) dispatched per-mode
disk/topology checks via reflection (`_validation_${INSTALL_MODE}`),
with the bodies (`_validation_single`, `_validation_multi`) sitting
in validation.sh itself. The Layout Module (`lib/layout-<mode>.sh`)
already owns every other mode-specific concern — planning,
partitioning, pool creation, ESP mount — via the adapter pattern
established for bootloaders (ADR 0003) and desktop environments
(ADR 0005). Validation was the odd one out: a Layout Module change
forced a validation.sh edit too. Adding a new layout mode meant
touching two files.

## Decision
Each Layout Adapter publishes `layout_validate` alongside
`layout_plan`, `layout_partition`, `layout_create_pools`,
`layout_mount_esp`. `validate_install_context` calls
`layout_validate` on the active adapter. The reflective dispatcher
and the `_validation_single`/`_validation_multi` bodies are
deleted.

`layout_validate` is a pure check — no state writes, no `LAYOUT_*`
population, exits via `error` on first failure. Pre-condition role
(input check) stays distinct from the existing post-condition
helpers `_layout_verify_plan_contract` /
`_layout_verify_partition_contract` (output check), which are not
renamed.

The active Layout Module is now sourced from `03-install.sh`
**before** `validate_install_context` runs (previously: after).
Unknown `INSTALL_MODE` fails at `source_module` time
("file not found") instead of at the dispatcher's
`declare -F` guard.

## Consequences
- Adding a new layout mode requires only a new
  `lib/layout-<mode>.sh` with the full interface — zero
  validation.sh changes.
- Deleting a layout module deletes its validator too — locality
  restored. Today's deletion-test was weak: removing
  `layout-single.sh` left `_validation_single` orphaned in
  validation.sh.
- Mode-specific validator tests move from `tests/validation*.bats`
  to `tests/layout-single.bats` / `tests/layout-multi.bats`,
  co-located with the adapter they test.
- `validate_install_context` shrinks to genuinely
  cross-cutting checks: hostname/locale/timezone, impermanence,
  persist, program preflight.
- Reordering the source line means the layout module is loaded
  even on dry/validate-only runs that never reach
  `layout_plan` — acceptable since sourcing has no side effects
  (functions defined, not called).
