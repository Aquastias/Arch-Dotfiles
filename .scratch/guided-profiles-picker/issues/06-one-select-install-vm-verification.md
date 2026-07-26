# End-to-end one-select install verification (VM)

Status: ready-for-agent

## Parent

.scratch/guided-profiles-picker/PRD.md
ADR: docs/adr/0055-guided-profiles-picker-and-default-secret-posture.md

## What to build

The composed-experience proof, run after the picker (02), secret posture (04),
and re-cut profiles (05) have landed. Drive the guided installer in a VM the way
an operator would for a one-select install and assert the machine that comes out
matches the profile.

Flow under test: boot the guided menu → `Profiles ▸ desktop` (seeds) → Proceed →
pick disk(s) → type `INSTALL`, with **no secret overrides** (everything defaults
to `12345`). Then the laptop single-disk variant.

## Acceptance criteria

- [ ] A guided run seeded from `desktop` installs with no secret input and boots
- [ ] The installed machine is encrypted, impermanent, and ssh-enabled ZFS with
      the `rpool` mirror + `data` raidz1 layout
- [ ] Root, the user, and the disk passphrase are `12345` (the applied defaults)
- [ ] `/home`, `/var/lib/docker`, `/var/lib/libvirt` survive an impermanence
      rollback (reboot)
- [ ] The `laptop` profile installs as encrypted single-disk ZFS the same way
- [ ] The `INSTALL` consent gate is exercised (install refuses without it)
- [ ] Realized as VM coverage alongside the existing `tests/vm/` guided suites

## Blocked by

- 02 — Profiles picker in the guided menu
- 04 — Secret override screen: tags + `Disk encryption` + age precedence
- 05 — Personal profiles re-cut (desktop + laptop)
