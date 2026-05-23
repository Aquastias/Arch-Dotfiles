Status: ready-for-agent

# layout-single.bats coverage

## Parent

`.scratch/tests-and-commons-cleanup/PRD.md`

## What to build

Add `.os/tests/layout-single.bats` to bring `lib/layout-single.sh`
to parity with `lib/layout-multi.sh`'s existing coverage.
`layout-single.sh` (277 lines) implements the Layout Module
interface (`layout_plan`, `layout_partition`, `layout_create_pools`,
`layout_mount_esp`) for the single-disk install path — the default
for most machines — and today has zero direct tests. Its sibling
multi-disk module is covered by `layout-multi.bats` plus shared
assertions in `layout-common.bats`.

Mirror the existing patterns:

- Stub `zfs`, `zpool`, `sgdisk`, and any other external commands by
  exporting bash functions that append argv to a `$CALLS` log
  (same approach as `chroot-impermanence.bats`)
- Assert against `$CALLS` plus the `LAYOUT_*` published outputs
  (`LAYOUT_ESP_PARTS[]`, `LAYOUT_OS_POOL_NAME`,
  `LAYOUT_DATA_POOL_NAME`) — never against mode-private globals
  (`SINGLE_*`)
- Per-test `mktemp -d` isolation

## Acceptance criteria

- [ ] `tests/layout-single.bats` exists and exercises each of
      `layout_plan`, `layout_partition`, `layout_create_pools`,
      `layout_mount_esp`
- [ ] Tests cover at least the same scenarios as `layout-multi.bats`
      (happy path + the documented edge cases)
- [ ] Tests assert only on `LAYOUT_*` published state, not on
      `SINGLE_*` or other mode-private globals
- [ ] All tests pass on a clean checkout
- [ ] Full bats suite passes

## Blocked by

None - can start immediately
