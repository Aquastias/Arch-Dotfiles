Status: done

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

- [x] A bats file assembles the real generator output (real `nonzfs_hooks`/
      `btrfs_hooks` → `_initcpio_hooks_line`) into a real `mkinitcpio.conf`
      and builds it with real `mkinitcpio -c … -g /dev/null --nopost` — a
      strict superset of `-n` (it actually resolves + builds the hooks).
      SKIP per-hook-absent via a new shared helper
      (`validators_skip_unless_hooks_installable`). Runs for REAL on the dev
      host for ext4, encrypted-ext4, and btrfs-multi; SKIPs zfs +
      btrfs-rollback off an archzfs env.
- [x] Order asserts covering the modprobe-before-root-mount class: the
      per-filesystem builder ordering already lives in `layout/*-boot.bats`
      (kept — see below); the validator adds the one thing they miss, that
      the chroot **generator** preserves the encrypt/block → filesystems
      pivot end-to-end, plus a scrambled-line regression giving it teeth.
- [x] **No trim applies (correction to the original AC).** `mkinitcpio`
      does not enforce HOOKS ordering, so it cannot subsume the
      `layout/*-boot.bats` ordering regexes; and `chroot-initcpio.bats` is
      pure logic (modconf→kmod swap, udev override) the validator does not
      cover. There is no redundant assertion to delete without losing real
      unit coverage, so this slice is purely additive (real build
      validation). Duplicate positive order asserts were removed from the
      validator during review so it does not re-add the layout tests' checks.
- [x] `tests/run.sh` passes (1844 tests, 0 fail). `tests/shellcheck.sh`
      unaffected (globs `*.sh`; the added `.bash`/`.bats` are out of scope;
      harness verified clean via `shellcheck -x`).

## Blocked by

- Issue 01 (shares `tests/lib/validators.bash`).
