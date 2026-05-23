Status: ready-for-agent

# finalize.bats tracer-bullet

## Parent

`.scratch/tests-and-commons-cleanup/PRD.md`

## What to build

Add `.os/tests/finalize.bats`, a tracer-bullet test covering
`lib/finalize.sh` (66 lines, currently uncovered). The script runs
pool export + cleanup at the end of `install.sh`; a regression that
leaves the OS pool imported would strand the machine on next boot.

The test does not need to be exhaustive — one happy-path scenario
that proves the finalize flow calls `zpool export` for each
relevant pool is enough.

Patterns to follow:

- Stub `zpool` and `umount` as bash functions appending argv to a
  `$CALLS` log (same as `chroot-impermanence.bats`)
- Set the input env vars (`LAYOUT_OS_POOL_NAME`,
  `LAYOUT_DATA_POOL_NAME`) per scenario
- Per-test `mktemp -d` isolation

## Acceptance criteria

- [ ] `tests/finalize.bats` exists
- [ ] One test asserts `zpool export <os_pool>` is called when only
      `LAYOUT_OS_POOL_NAME` is set
- [ ] One test asserts both `zpool export` calls are made when
      `LAYOUT_DATA_POOL_NAME` is also set
- [ ] Stub-call-log assertions only — no real `zpool` invocations
- [ ] Full bats suite passes

## Blocked by

None - can start immediately
