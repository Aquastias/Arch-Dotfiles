Status: done

# KDE + encryption VM fixture

## Parent

`.scratch/impermanence/PRD.md`

## What to build

Add a VM integration fixture that exercises impermanence on a ZFS-native-encrypted pool with KDE installed. The most important property under test is initramfs hook ordering: the existing ZFS hook prompts for the encryption passphrase and unlocks the pool, then the new Rollback Hook runs against the unlocked pool, then `filesystems` mounts. If the Rollback Hook runs before unlock, it cannot see the Rollback Datasets and fails closed — that failure mode is the regression risk this fixture catches.

Scope:

- New fixture `tests/vm/testing-single-disk-impermanent-kde-encrypted.sh`. Built from `testing-single-disk-impermanent.sh` (slice 1) with `options.encryption=true` and KDE enabled. Reference the existing KDE fixture pattern for SDDM verification.
- Configuration: single-disk, KDE, encryption on, impermanence enabled with defaults.
- The fixture must drive the encryption passphrase prompt during install (existing fixtures for the encryption path establish how this is done — reuse the same pattern).
- Post-install assertions (beyond the slice 1 baseline):
  - The pool is encrypted (`zfs get encryption rpool` confirms)
  - The first boot prompts for the passphrase (or the test driver supplies it via the same mechanism the existing encryption fixtures use)
  - All Rollback Datasets are rolled back to `@blank` post-passphrase, pre-mount — i.e. the boot succeeds and the curated identity files are present from `/persist`
  - SSH host key persists across reboot
  - An unpersisted edit vanishes across reboot
  - SDDM reaches the login screen after reboot
- The fixture intentionally does NOT layer SOPS on top — that combination is slice 7's responsibility. Keep this fixture focused on encryption + impermanence.

If during implementation the Rollback Hook turns out to need an explicit `After=` ordering relative to the ZFS unlock hook (rather than just appearing later in `HOOKS=`), record the finding in a comment in the hook install script and add an assertion to this fixture that the ordering is preserved.

## Acceptance criteria

- [ ] `tests/vm/testing-single-disk-impermanent-kde-encrypted.sh` provisions a single-disk KDE install with ZFS encryption and impermanence enabled
- [ ] Install prompts for the encryption passphrase using the existing fixture mechanism
- [ ] Boot succeeds: passphrase unlocks the pool, Rollback Hook reverts all Rollback Datasets to `@blank`, `filesystems` mounts cleanly
- [ ] All curated persist mounts are active post-boot
- [ ] SSH host key persists across reboot
- [ ] Unpersisted `/etc` edit disappears after reboot
- [ ] SDDM reaches the login screen after reboot

## Blocked by

- `.scratch/impermanence/issues/01-core-impermanence.md`
- `.scratch/impermanence/issues/03-pacman-resnapshot-hook.md`
