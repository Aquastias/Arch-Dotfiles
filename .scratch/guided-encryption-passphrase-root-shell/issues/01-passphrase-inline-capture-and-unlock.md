# Encryption passphrase: inline capture → manifest → back-end unlock

Status: ready-for-agent

## Parent

`.scratch/guided-encryption-passphrase-root-shell/PRD.md` (ADR 0054)

## What to build

The complete happy path for capturing the ZFS/LUKS encryption passphrase in the
Guided Installer the same inline-masked way as the root/user passwords, and using
it to unlock the pool at boot — with the existing back-end tty prompt kept as a
fallback for non-guided installs.

An operator building an encrypted host sees an `encryption password` row on the
Disks screen (only when encryption is on), types the passphrase masked and
confirmed inside the menu, and the installed machine unlocks at first boot with
exactly what they typed. A profile/manual install is unaffected — it still gets
the back-end prompt.

Reuses the existing inline-masked secret screen (ADR 0051) via a new `enc`
target; the Secrets Manifest / `.guided_passwords.*` no-SOPS seam (ADR 0049); and
`collect_enc_passphrase`.

## Acceptance criteria

- [ ] An `encryption password` row renders on the Disks screen directly under the
      `encryption` toggle, **only when encryption is on**, reading `(set)` /
      `(not set)` — never the value.
- [ ] Enter on the row opens the existing inline-masked secret screen (masked
      bullets, cursor-unbound, type-twice confirm) via a new `enc` secret target.
- [ ] First entry shorter than 8 chars emits a notice and stays on the entry
      screen (ZFS `keyformat=passphrase` minimum); an 8+ entry proceeds to
      confirm.
- [ ] A matching confirm writes the value to the Secrets Manifest under
      `enc_passphrase`; a mismatch restarts entry (as with passwords).
- [ ] On an fzf too old for the masking binds, entry degrades to the ADR 0049
      `execute()` masked prompt via the same rich-chrome gate the password rows
      use.
- [ ] The guided injector stages `enc_passphrase` into install-state under the
      `.guided_passwords.*` family; `.secrets.*` stays untouched (no SOPS
      activation). The value never enters Config State and is never emitted by
      Save/Export.
- [ ] `collect_enc_passphrase` resolves `ZFS_PASSPHRASE` by precedence
      `INSTALL_ENC_PASSPHRASE` → guided manifest value → interactive tty prompt;
      the prompt still works when neither preset is present.
- [ ] `tests/config/guided-controller.bats`: the Disks row appears only when
      encryption is on; Enter navigates to the `enc` secret screen; a `<8` first
      entry notices-and-stays; a valid type-twice writes the manifest and returns.
- [ ] `tests/config/guided-secrets.bats`: an `enc_passphrase` in the manifest
      lands as its decrypted file + the `.guided_passwords.*` seam, `.secrets.*`
      untouched.
- [ ] Back-end resolution covered (prior art `tests/secrets.bats`): each
      precedence tier yields the right `ZFS_PASSPHRASE`.
- [ ] VM `arch-zfs-test-guided-secure` still passes: the guided→manifest→
      `collect_enc_passphrase` handoff drives the real passphrase-unlock path via
      the `INSTALL_ENC_PASSPHRASE` preset.

## Blocked by

- None — can start immediately.
