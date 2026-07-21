Status: done

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

- [x] A bats file (`tests/profiles/user-units-validate.bats`) runs every
      REAL shipped `programs/*/services/*.service` (discovered dynamically)
      through `systemd-analyze verify --user` via the shared harness
      (`validators_verify_user_unit`), tolerating only the target-only
      environmental classes (ExecStart binary "is not executable",
      dependency "Unit … not found") and failing on structural errors. A
      regression proves an injected unknown directive is caught.
- [~] **Loader entries deferred to the VM tier (issue 06).** The systemd-boot
      emitter (`lib/chroot/bootloader-systemd-boot.sh`) is a chroot script
      that runs `bootctl install` + writes hardcoded `/boot/efi` heredocs —
      no pure emitter / `ROOT` / `LIB_ONLY` seam to capture output
      unprivileged (confirmed in review). Faithfully validating its real
      output requires a booted/rooted env, so the loader-conf key checks
      live in the VM smoke tier, not here. Recorded rather than faked.
- [x] **Known limit (documented in the harness):** a dependency-NAME typo
      (`Requires=typo.service`) is indistinguishable from a legit missing
      external dep on the dev host — both read "Unit X not found" — so this
      tier catches malformed unit SYNTAX, not dep typos; the VM tier catches
      those once deps are present.
- [x] **No trim applies.** `profiles-user-services.bats` tests the resolver/
      enable/symlink logic, not unit content; nothing is subsumed. Additive.
- [x] `tests/run.sh` passes (0 fail). `tests/shellcheck.sh` unaffected
      (globs `*.sh`; harness `shellcheck -x` clean).

## Blocked by

- Issue 01 (shares `tests/lib/validators.bash`).
