Status: ready-for-agent

# `persist_unapply` + `persist_restore_data`, migrate runtime `cmd_remove`

## Parent

`.scratch/persist-verbs-extraction/PRD.md`

## What to build

Add two functions to `lib/impermanence-common.sh`:

- `persist_unapply <target>` — stop the Persist Mount, remove the unit
  file, remove the tmpfiles entry, daemon-reload. No data movement.
- `persist_restore_data <target>` — move data from the Persist Dataset
  back to the live path. Used only by runtime `remove --yes`.

Refactor `tools/impermanence.sh::cmd_remove`:

- Default (no `--yes`): `persist_unapply` + host-config undeclare. Data
  at `/persist/<path>` is left untouched.
- With `--yes`: `persist_unapply` + host-config undeclare +
  `persist_restore_data`.

Remove the now-duplicated local helpers (`stop_and_reload`,
`remove_tmpfiles_entry`, `move_data_back`). The host-config jsonc edit
stays in the tool.

Default safety is preserved: `remove` without `--yes` cannot destroy
persisted data.

## Acceptance criteria

- [ ] `persist_unapply` and `persist_restore_data` exist in
      `lib/impermanence-common.sh`
- [ ] Both functions are covered by bats tests; idempotency case
      (`persist_unapply` on a non-existent target is a no-op) is
      included
- [ ] `tools/impermanence.sh::cmd_remove` composes the two verbs;
      duplicated local helpers are removed
- [ ] `tests/impermanence-tool.bats` `remove` cases (default and
      `--yes`) pass unmodified
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

- `.scratch/persist-verbs-extraction/issues/01-persist-apply-and-stage-copy.md`
