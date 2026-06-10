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

## Comments

### Agent VM run (Claude) — 2026-06-10

Ran the gates on the local libvirt host (KVM). Results + fixes:

- [x] **`single/plain`** install exits 0. First run OOM-killed building
      `paru` (rustc LTO) at 4 GiB — `install:"repo"` now resolves to a real
      host profile whose primary user pulls AUR. Fixes: (a) the regression
      where `install:"repo"`→`VM_DEFAULT_HOST_PROFILE` was `desktop` (now a
      2-disk mirror, breaking the single-disk smoke) — repointed the default
      to `arch-kde` (`vm/lib/profile.sh`); (b) bumped `single/plain` RAM
      4→8 GiB. Re-run: `===INSTALLER-EXIT-0===`.
- [x] **`data-pools/reorder`** boot-verify reached the first-boot sentinel
      (by-id + pools) under permuted disks. Surfaced a spurious
      `[ERROR] Installer failed at line 290` from the Data-Pool Ownership
      step (see issue 08) — cosmetic for this no-user inline profile; fixed.
- [x] **`desktop/kde`** boots into KDE/SDDM. Install completed + the disk is
      bootable (SDDM Plasma login confirmed by `virsh screenshot`). Found +
      fixed a harness bug: the persistent flow left the install ISO attached
      with `--boot cdrom,hd`, so the reboot landed on the live ISO. Added a
      shared `_vm_eject_cdroms` (`vm/lib/core.sh`) and call it before the
      final boot in `flow-persistent.sh` (the test flow already ejected).
- [~] **`headless/secure`**: per the operator, the install passphrases are
      now hardcoded for the disposable VM (test-only) — `INSTALL_ENC_PASSPHRASE`
      (`lib/zfs/pools.sh`) + `SECRETS_AGE_PASSPHRASE` (`lib/secrets.sh`)
      seams, supplied by both VM flows. The install runs unattended; the
      encrypted root still prompts for the ZFS passphrase once at boot
      (`testtest`) — unavoidable, enter it via virt-manager for the checklist.

All bats green throughout (1048). Fixes also touched the Profiles Runner
(see issue 08).
