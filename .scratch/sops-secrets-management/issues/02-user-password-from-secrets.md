Status: done

# User password from User Secrets

## Parent

`.scratch/sops-secrets-management/PRD.md`

## What to build

Extend `lib/chroot/create-user.sh` to read the initial user password from the decrypted User Secrets tmpfs file when available, falling back to the hardcoded `12345` default when not.

End-to-end behaviour: if `install-state.json` contains a `secrets.users.<username>` key pointing to a decrypted secrets file, and that file has a `password` field, use that value when calling `chpasswd`. Otherwise behave exactly as before.

No changes to the secrets file schema — the `password` field is already defined in the PRD.

## Acceptance criteria

- [ ] When `install-state.json` has no `secrets.users.<username>` entry: user is created with password `12345` (existing behaviour unchanged)
- [ ] When the entry is present but the decrypted file has no `password` field: falls back to `12345`
- [ ] When `password` is present in the decrypted file: `chpasswd` receives that value
- [ ] BATS tests cover: no secrets entry, secrets entry without password field, secrets entry with password field

## Blocked by

- `.scratch/sops-secrets-management/issues/01-secrets-module.md`
