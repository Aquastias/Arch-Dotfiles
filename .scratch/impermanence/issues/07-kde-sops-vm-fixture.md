Status: ready-for-agent

# KDE + SOPS VM fixture

## Parent

`.scratch/impermanence/PRD.md`

## What to build

Add a VM integration fixture that exercises the most important cross-cutting integration: impermanence + SOPS + a real desktop environment (KDE). The fixture verifies that the Machine Age Key — derived at install time from `ssh_host_ed25519_key` via `ssh-to-age` and stored at `/etc/secrets/age/keys.txt` — survives across reboots by virtue of `/etc/ssh` and `/etc/secrets` both being in the Curated Persist Defaults. Without that survival, the SOPS Runtime Service would fail to decrypt secrets on second boot.

Scope:

- New fixture `tests/vm/testing-single-disk-impermanent-kde-sops.sh`. Closest sibling: the existing KDE + SOPS fixture (whichever among the `testing-env-kde*.sh` family covers SOPS), plus `testing-single-disk-impermanent.sh` from slice 1.
- Configuration: single-disk, KDE as the only desktop environment, SOPS enabled with at least one encrypted user secret and one host secret, impermanence enabled with defaults.
- Post-install assertions (beyond the slice 1 baseline):
  - `/etc/secrets/age/keys.txt` exists and is bind-mounted from `/persist/etc/secrets/age/keys.txt`
  - `/etc/ssh/ssh_host_ed25519_key` exists and is bind-mounted from `/persist/etc/ssh/ssh_host_ed25519_key`
  - SOPS Runtime Service decrypts secrets to `/run/secrets/` on first boot and on second boot (verify the same plaintext values appear after reboot)
  - The Machine Age Key public form is unchanged across reboot (run `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub` before and after; outputs match)
  - KDE/SDDM is enabled and reaches the login screen after reboot (existing assertion pattern from the KDE fixture)
- No new bats unit tests; the integration is what this fixture exists to cover.

This fixture is the canary for any future change that might disrupt the SOPS / age-key derivation pipeline under impermanence.

## Acceptance criteria

- [ ] `tests/vm/testing-single-disk-impermanent-kde-sops.sh` provisions a single-disk KDE install with SOPS and impermanence enabled
- [ ] `/etc/secrets/age/keys.txt` and `/etc/ssh/ssh_host_ed25519_key` are bind-mounted from `/persist` after install
- [ ] SOPS Runtime Service successfully decrypts secrets on first boot
- [ ] After reboot, SOPS Runtime Service decrypts the same secrets to the same plaintext values
- [ ] The Machine Age Key public form (`ssh-to-age` output) is identical across reboot
- [ ] SDDM reaches the login screen after reboot

## Blocked by

- `.scratch/impermanence/issues/01-core-impermanence.md`
- `.scratch/impermanence/issues/03-pacman-resnapshot-hook.md`
