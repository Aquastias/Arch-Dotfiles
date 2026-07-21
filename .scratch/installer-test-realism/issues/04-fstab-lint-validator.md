Status: ready-for-agent

# fstab syntax/field lint validator

## Parent

`.scratch/installer-test-realism/PRD.md`

## What to build

Reuse the `tests/lib/validators.bash` harness (issue 01). Run the real
fstab generators (`write_fstab` / `_chroot_fstab_generate` /
`btrfs_root_fstab` / `data_group_fstab_line`) into a tmpdir and lint the
result: correct field count per line, sane mount options, plausible
mountpoints, no duplicate mountpoints, ESP/root/swap present as expected
per filesystem. Unprivileged — no `findmnt --verify` requirement.

Then trim the overlapping raw-string fstab assertions the lint now covers;
keep the UUID/branch-specific logic tests.

## Acceptance criteria

- [ ] A bats file lints real fstab output across the filesystem adapters
      (zfs, ext4, xfs, btrfs single + multi)
- [ ] A malformed-fstab regression (wrong field count / duplicate
      mountpoint) fails the lint
- [ ] Overlapping raw-string assertions removed from the fstab tests; net
      stub count down
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

- Issue 01 (shares `tests/lib/validators.bash`).
