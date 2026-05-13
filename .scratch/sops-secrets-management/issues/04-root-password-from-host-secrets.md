Status: ready-for-agent

# Root password from Host Secrets

## Parent

`.scratch/sops-secrets-management/PRD.md`

## What to build

Extend `lib/chroot/password.sh` to read the root password from the decrypted Host Secrets tmpfs file when available, falling back to the existing interactive prompt when not.

End-to-end behaviour: if `install-state.json` contains a `secrets.host` key pointing to a decrypted secrets file, and that file has a `root_password` field, use that value to set the root password non-interactively. Otherwise prompt the operator interactively as before.

## Acceptance criteria

- [ ] When `install-state.json` has no `secrets.host` entry: operator is prompted interactively (existing behaviour unchanged)
- [ ] When the entry is present but the decrypted file has no `root_password` field: falls back to interactive prompt
- [ ] When `root_password` is present in the decrypted file: root password is set non-interactively using that value, no prompt shown
- [ ] No plaintext password appears in process list or installer logs

## Blocked by

- `.scratch/sops-secrets-management/issues/01-secrets-module.md`
