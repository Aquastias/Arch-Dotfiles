# 04 — LUKS encryption for non-ZFS roots

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

Layer LUKS encryption onto the non-ZFS root path from issue 03. Reuse the
existing passphrase seam verbatim (`collect_enc_passphrase` / `prompt_secret` /
the `INSTALL_ENC_PASSPHRASE` VM seam) — only the consumer differs: pipe the same
secret to `cryptsetup luksFormat`/`luksOpen` instead of `zpool create`. The Root
Adapter's `ROOT_CMDLINE` becomes `root=/dev/mapper/cryptroot` with
`cryptdevice=UUID=…:cryptroot`, and its `HOOKS` gain `encrypt` before
`filesystems`. The swap partition is LUKS-wrapped when the root is encrypted.

## Acceptance criteria

- [ ] An encrypted ext4 root prompts once for the passphrase in initramfs and
      boots (live/HITL verify acceptable — encrypted roots can't headless
      boot-verify).
- [ ] The same passphrase seam is used as ZFS; the VM preset seam still works.
- [ ] `ROOT_CMDLINE` emits `cryptdevice=…:cryptroot` + `root=/dev/mapper/
      cryptroot`; `HOOKS` include `encrypt` before `filesystems`.
- [ ] Swap is LUKS-wrapped when the root is encrypted; plaintext when not.
- [ ] bats covers the encrypted-variant `ROOT_CMDLINE`/`HOOKS` emitters and the
      partition/LUKS planner with the encrypt flag set.

## Blocked by

- `03` (ext4 plaintext root tracer)
