# 07 — Console Answerer + GRUB serial parity + encrypted boot-verify

Status: ready-for-human
Type: AFK

## Implementation (code-complete; live encrypted boot = HITL)

- `vm/lib/console-answerer.sh` — pure prompt-matcher `console_answerer_variant`
  (encrypt-hook / systemd-cryptsetup / zfs-native), `_passphrase`, `_reply`, and
  the IO watcher `console_answerer_watch` (tails the serial log, writes the test
  passphrase to the char device once per prompt; handles multi-disk + no-newline
  cryptsetup prompts). Passphrase = `CONSOLE_ANSWERER_PASSPHRASE` (default
  `testtest` from `INSTALL_ENC_PASSPHRASE`).
- `vm/lib/flow-test.sh` — boot-verify now starts the Answerer against
  `virsh ttyconsole` and stops it in teardown + traps (harmless on plaintext).
- `vm/lib/seed-generator.sh` — GRUB serial parity: the test-only serial
  injection also appends `console=ttyS0` to `grub.cfg` linux lines.
- `lib/matrix/synth.sh` — oracle flip: encrypted cells boot-verify (no longer
  install-only); only gpu≠auto stays install-only.
- Tests: `tests/vm/console-answerer.bats` (9, incl. the watcher driven against a
  temp file as the char device), `tests/matrix/matrix-synth.bats` (flip).

## Remaining (live VM run — unattended, but not runnable inside the agent harness)

Fully automated (the Answerer types the passphrase over serial — no human at the
VM). NOT blocked by kvm (present) or human interaction. The blocker is the agent
execution harness: it kills any sandbox-disabled command that leaves a long-lived
background child (verified: `sleep &` → 0, `git daemon &` → 144), and the VM flow
backgrounds `script … virsh console` for console capture. So run it in a normal
host terminal:

    cd ~/.dotfiles
    ISO_URL_OVERRIDE="file:///home/aquastias/Downloads/archlinux-2026.07.01-x86_64.iso" \
    VM_RAM_MB=8192 MATRIX_DISK_GIB=40 \
    ./.os/tools/matrix.sh run zfs-single-enc     # zfs-native 'rpool' prompt
    #                          ext4-single-enc   # LUKS encrypt-hook prompt

Default REPO_URL = public GitHub HTTPS (has the encrypted installer; diff vs
cached origin/main is empty for .os/lib/layout|chroot + install.sh).

- AC2/AC3/AC4/AC5: live encrypted single-disk + GRUB + impermanent cells reach
  `===FIRSTBOOT-OK===` unattended; wrong/absent passphrase → boot-fail within the
  bounded timeout (the 125/124 path already bounds it). Live risk to confirm:
  writing the `virsh ttyconsole` pty while `virsh console` reads it, and the exact
  per-variant prompt strings.

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

- [x] The prompt-matcher returns detected + correct passphrase for each variant
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
