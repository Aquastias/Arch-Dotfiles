Status: ready-for-agent

# Initcpio HOOKS validator via `mkinitcpio -n` + order asserts

## Parent

`.scratch/installer-test-realism/PRD.md`

## What to build

Reuse the `tests/lib/validators.bash` harness (issue 01). Run the real
initcpio config generator (`lib/chroot/initcpio.sh`) into a tmpdir and
validate it with `mkinitcpio -n` (dry-run, no image write), plus explicit
HOOKS-order assertions targeting the modprobe/hook-ordering class — e.g.
`zfs`/`encrypt` placement relative to `filesystems`, root-fs module
availability before mount.

Then trim the overlapping `$CALLS`/raw-HOOKS assertions in the initcpio
tests the validator now covers for real; keep pure branch-selection logic.

## Acceptance criteria

- [ ] A bats file runs real `initcpio.sh` output through `mkinitcpio -n`
      (SKIP when `mkinitcpio` absent, via the shared harness)
- [ ] HOOKS-order assertions covering the historical
      modprobe-before-root-mount shape per filesystem (zfs, btrfs, xfs,
      ext4, encrypt)
- [ ] Overlapping `$CALLS`/raw-HOOKS assertions removed from the initcpio
      tests; net stub count down
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

- Issue 01 (shares `tests/lib/validators.bash`).
