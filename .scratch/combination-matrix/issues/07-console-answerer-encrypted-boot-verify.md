# 07 — Console Answerer + GRUB serial parity + encrypted boot-verify

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/combination-matrix/PRD.md`

## What to build

Make encrypted cells boot-verify **fully unattended** by driving the real
passphrase-unlock path — the closest-to-reality oracle, with no human keystroke.

- **Console Answerer** (`vm/lib/console-answerer.sh`, a VM Harness component) —
  its pure core is a prompt-matcher: given serial text, decide whether a
  disk-unlock prompt is present and which passphrase to send (patterns for the
  mkinitcpio `encrypt` hook, `systemd-cryptsetup`, and zfs-native `load-key`).
  The IO shell watches the serial log (the harness already injects
  `console=ttyS0` into the installed system, routing the prompt there) and writes
  the known test passphrase to the **serial char device** — not `virsh
  send-key`, because with `console=ttyS0` the prompt reads from `/dev/console`.
- **GRUB serial parity** — extend the existing systemd-boot loader-entry
  `console=ttyS0` injection with a `GRUB_CMDLINE_LINUX` equivalent so encrypted
  GRUB cells route their prompt to serial too.
- **Oracle flip** — encrypted cells stop being install-only: they now require
  the full boot-verify (first-boot sentinel, or `verify.rollback` for encrypted-
  impermanent). A missed/failed unlock returns `ENCRYPTED-BOOT-FAIL` within a
  bounded timeout rather than hanging.

The Answerer runs host-side and reads the `FIRSTBOOT-OK` sentinel back, so the
automation verifies itself — no HITL.

## Acceptance criteria

- [ ] The prompt-matcher returns detected + correct passphrase for each variant
      (encrypt hook / systemd-cryptsetup / zfs-native) and detected=false on
      non-prompt serial noise (unit-tested against captured serial text).
- [ ] An encrypted single-disk cell boots unattended: the Answerer supplies the
      passphrase over serial and the run observes `===FIRSTBOOT-OK===`.
- [ ] An encrypted GRUB-bootloader cell routes its prompt to serial and unlocks.
- [ ] An encrypted-impermanent cell passes `verify.rollback` unattended.
- [ ] A wrong/absent passphrase surfaces `ENCRYPTED-BOOT-FAIL` within the
      bounded timeout, never a 600 s hang.
- [ ] The oracle table treats encrypted the same as its plain/impermanent peer
      (no install-only carve-out).

## Blocked by

- `.scratch/combination-matrix/issues/05-vm-profile-synthesizer-oracle-dispatch.md`
