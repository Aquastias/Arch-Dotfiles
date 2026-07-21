Status: ready-for-agent

# Boot entries + user units via `systemd-analyze verify --user`

## Parent

`.scratch/installer-test-realism/PRD.md`

## What to build

Reuse the `tests/lib/validators.bash` harness (issue 01). Two validators:

- **systemd-boot loader entries** (`lib/chroot/bootloader-systemd-boot.sh`)
  — validate loader-conf / entry syntax and required keys
  (title/linux/initrd/options), including the serial-console cmdline
  injection the harness relies on.
- **Resolved user units** (`_profiles_resolve_user_unit`) — run through
  `systemd-analyze verify --user`.

Then trim the overlapping raw-string assertions in the boot / user-service
tests these validators now cover; keep pure resolution-logic tests. This
is the lowest historical bug-rate validator slice — land it last of the
four.

## Acceptance criteria

- [ ] A bats file validates real systemd-boot entries (SKIP when tooling
      absent, via the shared harness)
- [ ] A bats file runs real resolved user units through
      `systemd-analyze verify --user`
- [ ] Overlapping raw-string assertions removed from the boot /
      user-service tests; net stub count down
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

- Issue 01 (shares `tests/lib/validators.bash`).
