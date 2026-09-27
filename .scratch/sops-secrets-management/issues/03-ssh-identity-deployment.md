Status: done

# SSH identity deployment

## Parent

`.scratch/sops-secrets-management/PRD.md`

## What to build

Extend `lib/chroot/create-user.sh` to deploy an SSH identity private key to the new user's home directory when User Secrets contains one.

End-to-end behaviour: after the user is created, if the decrypted User Secrets file contains `ssh_identity_private_key`, write it to `~/.ssh/id_<type>` with permissions `600`, then derive the public key with `ssh-keygen -y` and write it to `~/.ssh/id_<type>.pub`. The key type is read from `ssh_identity_key_type` in the same secrets file; it accepts `ed25519`, `rsa`, or `ecdsa` and defaults to `ed25519` if absent.

If neither field is present in the secrets file, no SSH identity files are written.

## Acceptance criteria

- [x] No `ssh_identity_private_key` in secrets: no `~/.ssh/id_*` files written
- [x] `ssh_identity_key_type: ed25519` (or absent): key written to `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub`
- [x] `ssh_identity_key_type: rsa`: key written to `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`
- [x] `ssh_identity_key_type: ecdsa`: key written to `~/.ssh/id_ecdsa` and `~/.ssh/id_ecdsa.pub`
- [x] Private key file has permissions `600`; public key file has permissions `644`
- [x] Both files are owned by the created user
- [x] BATS tests cover: no key field, each of the three key types, missing key type defaults to ed25519

## Blocked by

- `.scratch/sops-secrets-management/issues/02-user-password-from-secrets.md`

## Comments

- 2026-09-27 audit: 556b35e.
