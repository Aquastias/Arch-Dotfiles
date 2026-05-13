Status: ready-for-agent

# Secrets Module (lib/secrets.sh)

## Parent

`.scratch/sops-secrets-management/PRD.md`

## What to build

Create `lib/secrets.sh` — the foundational secrets infrastructure for the installer. Wire it into `03-install.sh` immediately after `lib/config.sh`.

The module's responsibilities end-to-end:

1. Scan removable block devices (exclude the install target disk) for a file at `/age/key.age`.
2. If found, prompt the operator for the age key passphrase and decrypt the key to a ramfs/tmpfs path using `age --decrypt`.
3. Discover all `users/*/secrets.json` and `hosts/*/secrets.json` files present in the repo.
4. Decrypt each discovered secrets file with `sops --decrypt`, using `SOPS_AGE_KEY_FILE` pointing to the tmpfs key. Write each decrypted file to its own tmpfs path.
5. Write the tmpfs paths into `install-state.json` under `secrets.users.<username>` and `secrets.host` so chroot scripts can consume them via the existing `load-state.sh` mechanism.
6. Register a cleanup trap: clear all tmpfs secrets content unconditionally on exit (success or failure) after the chroot phase completes.
7. **Graceful no-op**: if no age key device is found AND no secrets files exist, print a notice and return without error — the install continues with default behaviour.

Also add a `.sops.yaml` template (with placeholder age recipient) at the repo root so operators know the expected structure.

## Acceptance criteria

- [ ] `lib/secrets.sh` is sourced by `03-install.sh` after `lib/config.sh`
- [ ] With no USB and no secrets files: module exits 0, `install-state.json` contains no `secrets.*` keys, install proceeds normally
- [ ] With a correct key and secrets files present: `install-state.json` contains `secrets.users.<name>` and `secrets.host` paths pointing to decrypted tmpfs files
- [ ] With a wrong passphrase: module exits non-zero with a clear error message before any disk operations
- [ ] Tmpfs is cleared after chroot exits regardless of success or failure
- [ ] BATS tests cover: no-op path, correct key path (fixture key + fixture secrets), wrong passphrase, tmpfs cleanup
- [ ] `.sops.yaml` template committed at repo root with `path_regex` covering `users/*/secrets.json` and `hosts/*/secrets.json`

## Blocked by

None — can start immediately.
