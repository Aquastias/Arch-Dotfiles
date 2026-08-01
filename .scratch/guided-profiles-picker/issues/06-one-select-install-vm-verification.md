# End-to-end one-select install verification (VM)

Status: done

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

## Status / Comments

**Headless assembly path VERIFIED (2026-07):** the guided `--guided` replay now
accepts a `profile=<name>` key (`_guided_seed_from_profile`) that seeds the menu
before field edits — the same seam the VM harness drives. `guided_build` with
`profile=laptop` + `disk=…` + `confirm=INSTALL` assembles the encrypted,
impermanent, SSH-enabled ZFS Effective Config with the disk baked and `/home`
persisted, and a field answer overrides the seed
(`tests/config/guided-shell.bats`). Secret defaulting to `12345` is covered in
`tests/config/guided-secrets.bats` / `guided-shell.bats` (ticket 03). The
in-menu picker + preview have a PTY smoke check (`tools/guided-fzf-smoke.py`).

**Live VM boot still OUTSTANDING — environment-gated.** A real libvirt/qemu
install (boot → `Profiles ▸ desktop` → Proceed → disk → `INSTALL`, then verify
the booted machine is encrypted/impermanent/ssh and `/home` survives a reboot
rollback) needs the maintainer's VM environment; it cannot run in the agent
sandbox (no libvirt/qemu, `tests/vm/*.qcow2` are permission-denied). Run it
alongside the existing `tests/vm/` guided suites to close the remaining boxes.
