Status: ready-for-agent

# `persist_apply` + `persist_stage_in_copy`, migrate runtime `cmd_add`

## Parent

`.scratch/persist-verbs-extraction/PRD.md`

## What to build

Add two functions to `lib/impermanence-common.sh`:

- `persist_apply <target> <kind>` — write the Persist Mount unit, write
  the tmpfiles entry, daemon-reload, start the mount. The runtime
  consumer needs reload+start; the install-time consumer (later
  slice) will skip reload via an opt-out (flag, env var, or split
  function — implementer's choice; document in the function header).
- `persist_stage_in_copy <target>` — copy live data to the Persist
  Dataset via `cp -a`. Used by the runtime tool because the bind mount
  activates immediately and the original must remain until covered.

Refactor `tools/impermanence.sh::cmd_add` to compose these two verbs.
Remove the now-duplicated local helpers (`write_mount_unit`,
`append_tmpfiles_entry`, `copy_live_data`, `reload_and_start`). The
host-config jsonc edit stays in the tool — not in the verbs.

CLI surface is unchanged. Failure-rollback behavior is preserved
(partial materialization is cleaned up).

## Acceptance criteria

- [ ] `persist_apply` and `persist_stage_in_copy` exist in
      `lib/impermanence-common.sh`
- [ ] Both functions are covered by bats tests in
      `tests/impermanence-common.bats` (new file) or extension of an
      existing one — assertions against a temp `ROOT`, idempotency
      cases included
- [ ] `tools/impermanence.sh::cmd_add` composes the two verbs;
      duplicated local helpers are removed
- [ ] `tests/impermanence-tool.bats` `add` cases pass unmodified
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

None - can start immediately.
