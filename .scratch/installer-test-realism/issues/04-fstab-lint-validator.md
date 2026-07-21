Status: done

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

- [x] A bats file (`tests/chroot/fstab-lint.bats`) lints the REAL fstab
      generators via `validators_fstab_lint`: `_chroot_fstab_generate`
      (1/2/3 ESPs), `btrfs_root_fstab` (UUID src single + `/dev/mapper`
      src for encrypted/multi — same generator), `data_group_fstab_line`,
      and an ASSEMBLED ESP+btrfs fstab (write_fstab's real shape — the
      duplicate-mountpoint check nothing did before).
- [~] **Adapter coverage caveat.** ext4/xfs **root** fstab lines are built
      inline inside the disk-touching `_root_format_and_mount`
      (`nonzfs/root.sh`), which has no pure emitter to call unprivileged, so
      they are validated in the VM tier, not here. The zfs "tail" is a bare
      comment (`# ZFS datasets are auto-mounted…`) — nothing to lint. ESP +
      btrfs (single/multi/enc) + data-group lines are covered for real.
- [x] Regressions with teeth: a duplicate mountpoint and a 5-field
      (malformed) line both fail the lint.
- [x] **No trim applies (correction to the AC).** The lint checks structure
      (fields, mountpoint plausibility, dump/pass, duplicates); the existing
      `chroot-fstab.bats` asserts business values (which UUID mounts where,
      umask). The lint does not subsume those, so nothing can be deleted
      without losing coverage. This slice is purely additive.
- [x] `tests/run.sh` passes (0 fail). `tests/shellcheck.sh` unaffected
      (globs `*.sh`; `.bash`/`.bats` out of scope; harness `shellcheck -x`
      clean).

## Blocked by

- Issue 01 (shares `tests/lib/validators.bash`).
