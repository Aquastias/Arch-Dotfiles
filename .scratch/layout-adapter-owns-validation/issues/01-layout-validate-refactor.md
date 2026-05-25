Status: ready-for-agent

# Move mode-specific validation into Layout Adapters

## Parent

`.scratch/layout-adapter-owns-validation/PRD.md` (ADR 0014)

## What to build

Move mode-specific disk/topology validation from
`lib/validation.sh` into each Layout Adapter as a new
`layout_validate` verb on the Layout Module interface.
`validate_install_context` calls `layout_validate` on the active
adapter; the reflective dispatcher
(`_validation_${INSTALL_MODE}`) and the `declare -F` mode-guard
disappear. The active Layout Module is sourced **before**
`validate_install_context` runs (today: after), so the dispatcher
has the active adapter available.

`layout_validate` is a pure check — no state writes, no
`LAYOUT_*` population. Exits via `error` on first failure. Bodies
move verbatim from the existing `_validation_single` and
`_validation_multi` functions. The pre-condition role
(`layout_validate`) stays distinct from the existing
post-condition helpers (`_layout_verify_plan_contract`,
`_layout_verify_partition_contract`) — those are not renamed.

Cross-cutting validators (`_validation_system_fields`,
`_validation_impermanence`, `_validation_persist`,
`_validation_preflight_programs`) stay in `lib/validation.sh`
unchanged — they are not layout-specific.

Per-mode validator test cases relocate from
`tests/validation*.bats` to `tests/layout-single.bats` /
`tests/layout-multi.bats`, co-located with the adapter they
test. Coverage parity is preserved — every assertion currently
made by `_validation_single` / `_validation_multi` must still
fire in the new location, with identical error messages.

Single commit. Splitting would leave the repo broken on
intermediate states (e.g. deleting `_validation_*` without
adding `layout_validate` fails the install). `CONTEXT.md` is
already updated.

## Acceptance criteria

- [ ] `layout_validate` is defined in `lib/layout-single.sh`
      with the body of the current `_validation_single`.
- [ ] `layout_validate` is defined in `lib/layout-multi.sh`
      with the body of the current `_validation_multi`.
- [ ] `lib/validation.sh` no longer defines `_validation_single`
      or `_validation_multi` and no longer contains the
      `declare -F "$validator"` mode-guard. `validate_install_context`
      calls `layout_validate` directly.
- [ ] In `03-install.sh`, `source_module
      "${SCRIPT_DIR}/lib/layout-${INSTALL_MODE}.sh"` happens
      between `detect_mode` and `validate_install_context`
      (today it happens after).
- [ ] An unknown `INSTALL_MODE` value fails at `source_module`
      time with a clear file-not-found message (not at the
      removed `declare -F` guard).
- [ ] Validator test cases for the single-disk mode live in
      `tests/layout-single.bats`; multi-disk cases live in
      `tests/layout-multi.bats`. Cases removed from
      `tests/validation*.bats`.
- [ ] Every pre-existing assertion (disk-missing, bad-topology,
      no-disks-in-group, missing-group-disk) still fires with
      the same error message in the new location.
- [ ] `shellcheck` passes on every changed file.
- [ ] `bats` runs cleanly across the full suite.
- [ ] Cross-cutting validators (`_validation_system_fields`,
      `_validation_impermanence`, `_validation_persist`,
      `_validation_preflight_programs`) are untouched.
- [ ] `LAYOUT_*` published globals are untouched.
- [ ] Single commit, conventional-commit style, capitalized
      after the prefix.

## Blocked by

None - can start immediately.
