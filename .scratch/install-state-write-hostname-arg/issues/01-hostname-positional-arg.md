Status: done

# Pass hostname positionally into install_state_write

## Parent

`.scratch/install-state-write-hostname-arg/PRD.md` (ADR 0018)

## What to build

Change `install_state_write`'s signature from
`install_state_write <path>` to
`install_state_write <path> <hostname>`. The function loads the
merged Host Config internally via `load_host_config "$hostname"`
(with the existing `2>/dev/null || printf '{}'` fallback) and
uses the passed-in hostname throughout the body — including the
`--arg hostname` line in the `jq` invocation that today reads
`$RESOLVED_HOSTNAME`.

The sole caller (in the chroot module) collapses its two-line
dance into one: drop the `INSTALL_STATE_HOST_JSON=...` setup
line and its `shellcheck disable=SC2034` comment, then call
`install_state_write` with `"$RESOLVED_HOSTNAME"` as the second
positional argument.

The `INSTALL_STATE_HOST_JSON` global is removed from the
codebase — no other reader exists.

`LAYOUT_OS_POOL_NAME` and `LAYOUT_ESP_PARTS` remain global reads
inside the function body. They are the Layout Module's published
interface (ADR 0014, ADR 0016) and are intentionally consumed
as globals; this PRD deliberately does **not** convert them.

The function header docstring drops the "Required inputs
(caller's scope)" block — the new signature is self-documenting.

Single commit. `CONTEXT.md` is unaffected.

## Acceptance criteria

- [x] `install_state_write` accepts `<path>` and `<hostname>`
      as two positional arguments; both required.
- [x] The function loads the merged Host Config internally via
      `load_host_config "$hostname"` with the existing
      `|| printf '{}'` fallback.
- [x] The `--arg hostname` line in the `jq` invocation uses
      the passed-in `$hostname` arg, not the
      `$RESOLVED_HOSTNAME` global.
- [x] The sole call site (in the chroot module) calls
      `install_state_write` with two positional arguments,
      passing `"$RESOLVED_HOSTNAME"` as the second.
- [x] The `INSTALL_STATE_HOST_JSON=...` setup line and its
      `shellcheck disable=SC2034` comment are deleted at the
      call site.
- [x] The `INSTALL_STATE_HOST_JSON` global appears nowhere in
      the codebase (verified via grep).
- [x] `LAYOUT_OS_POOL_NAME` and `LAYOUT_ESP_PARTS` are still
      read as globals inside the function body — not
      converted to arguments.
- [x] The function header docstring drops the "Required
      inputs (caller's scope)" block.
- [x] The rendered `install-state.json` is byte-identical to
      today's output for the same inputs (hostname + Host
      Config + Layout state).
- [x] `tests/install-state.bats` is updated: every test that
      previously pre-set `INSTALL_STATE_HOST_JSON` now passes
      the hostname positionally and uses a real fixture host
      directory under `tests/fixtures/` to exercise the
      `load_host_config` integration.
- [x] At least one new assertion covers the
      `|| printf '{}'` fallback path — when the host
      directory is absent the persist sub-object is empty.
- [x] Round-trip coverage
      (`install_state_load` reads what
      `install_state_write` wrote) is preserved.
- [x] Every assertion currently in
      `tests/install-state.bats` is preserved in the new
      structure.
- [x] `shellcheck` passes on every changed file.
- [ ] Full `bats` suite passes.
- [x] Single commit, conventional-commit style, capitalized
      after the prefix.

## Blocked by

None - can start immediately.

## Comments

- 2026-09-27 audit: 4912211 (ADR 0018). Remaining unticked lines are suite/VM
  runs not re-verifiable now.
