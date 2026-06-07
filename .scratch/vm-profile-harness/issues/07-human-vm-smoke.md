# Human VM smoke — verify the profile inventory boots

Status: ready-for-human

## Parent

`.scratch/vm-profile-harness/PRD.md`

## What to build

The closing human verification gate: run representative VM Profiles on a
real libvirt host and confirm the unified harness provisions them
correctly. This is the manual sign-off the AFK slices defer, matching the
repo's "human VM runs last" pattern. No code is written here — failures
are filed back against the relevant slice.

Representative coverage:

- **Persistent:** `vm.sh --profile desktop/kde` builds a usable VM that
  reboots into KDE/SDDM.
- **Test, repo config:** `vm.sh --testing --profile single/plain` installs
  and exits 0.
- **Test, secure:** `vm.sh --testing --profile headless/secure` exercises
  SOPS + impermanence + ZFS encryption + mirror (type `test` at the age
  passphrase prompt); spot-check the post-reboot checklist (Blank
  Snapshots, Persist mount, SOPS Runtime Service, host-key persistence).
- **Test, data-pools reorder:** `vm.sh --testing --verify-boot --profile
  data-pools/reorder` reaches the first-boot sentinel with by-id +
  pool-owners assertions after disks are permuted.

## Acceptance criteria

- [ ] `desktop/kde` boots into the installed KDE desktop.
- [ ] `single/plain` install completes with exit 0.
- [ ] `headless/secure` installs; post-reboot checklist passes.
- [ ] `data-pools/reorder` passes boot-verify (sentinel + by-id + owned)
      under permuted disk order.
- [ ] Any failure is filed against the owning slice; PRD marked done once
      all pass.

## Blocked by

- `.scratch/vm-profile-harness/issues/04-persistent-profiles-delete-wrappers.md`
- `.scratch/vm-profile-harness/issues/05-test-profiles-delete-wrappers.md`
