Status: ready-for-agent

# PRD: SOPS Secrets Management

## Problem Statement

The installer currently has no secrets management. Initial user passwords are hardcoded as `12345`, the root password is prompted interactively on every install, and SSH identity private keys cannot be provisioned to new machines at all. This means every fresh install requires a manual password change and SSH key setup before the machine is usable, and there is no way to store these credentials securely in the repo for fully-automated installs.

## Solution

Introduce optional SOPS-based secrets management. Operators encrypt initial passwords and SSH identity private keys into per-user and per-host `secrets.json` files committed to the repo. At install time, the operator provides a passphrase-protected age key on a USB stick; the Secrets Module decrypts secrets to a tmpfs and threads them to chroot scripts. After install, the machine's age key is derived from its SSH host key and printed so the operator can re-encrypt secrets for boot-time decryption. A SOPS Runtime Service decrypts secrets to `/run/secrets/` on every boot without operator interaction.

SOPS is fully optional. Installs without any `secrets.json` files fall back to the existing behaviour: user password defaults to `12345`, root password is prompted interactively.

## User Stories

1. As an operator, I want my real user passwords stored encrypted in the repo, so that I don't have to set them manually after every install.
2. As an operator, I want my SSH identity private key deployed to new machines during install, so that outgoing SSH works immediately on first boot.
3. As an operator, I want to configure the SSH key type per user (ed25519, rsa, ecdsa), so that I can match my existing key infrastructure.
4. As an operator, I want SOPS to be entirely optional, so that I can run the installer without any secrets setup and the existing behaviour is preserved.
5. As an operator, I want the installer to find my age key automatically from a USB stick at a known path, so that I don't have to specify its location.
6. As an operator, I want to be prompted for my age key passphrase at install time, so that my key file is safe even if the USB is lost or stolen.
7. As an operator, I want the machine's age public key printed after install completes, so that I know what to add to `.sops.yaml` for runtime decryption.
8. As an operator, I want the exact `sops updatekeys` command printed after install, so that I can enable runtime decryption without consulting documentation.
9. As an operator, I want the root password stored encrypted in host secrets, so that it is not hardcoded anywhere in the repo or install process.
10. As an operator, I want the root password to fall back to an interactive prompt if no host secrets file exists, so that existing installs without SOPS are not broken.
11. As an operator, I want decrypted secrets to live in a tmpfs during install, so that plaintext credentials are never written to persistent storage on the live ISO.
12. As an operator, I want the tmpfs cleared after the chroot phase completes, so that decrypted credentials do not linger in memory once they are no longer needed.
13. As an operator, I want the runtime SOPS service to decrypt secrets to `/run/secrets/` on every boot, so that services can access secrets after installation without the USB present.
14. As an operator, I want the runtime SOPS service to set correct ownership and permissions on each decrypted secret file, so that services can read them without running as root.
15. As an operator, I want the runtime SOPS service installed as a security system program, so that it is opted into via host config like any other security program.
16. As an operator, I want SOPS skipped entirely when no age key is found and no secrets files exist, so that the install continues normally without a USB key plugged in.
17. As an operator, I want per-user secrets co-located with the user's config directory, so that adding secrets for a new user is consistent with adding their config.
18. As an operator, I want per-host secrets co-located with the host's config directory, so that host-specific secrets follow the same pattern as host-specific config.
19. As a developer, I want `.sops.yaml` at the repo root to declare age recipients, so that there is a single source of truth for who can encrypt and decrypt secrets.
20. As a developer, I want the machine age key derived from the SSH host key via `ssh-to-age`, so that no new key material is introduced beyond what the installer already generates.
21. As a developer, I want the Secrets Module to be a self-contained lib module, so that it can be sourced and tested in isolation from the rest of the install flow.
22. As an operator, I want clear README instructions for generating an age key, password-protecting it, and placing it on a USB stick, so that I can set up secrets management from scratch.
23. As an operator, I want clear README instructions for the post-install `sops updatekeys` workflow, so that the runtime service works after the first machine install.

## Implementation Decisions

### New: Secrets Module

A new `lib/secrets.sh` module runs immediately after `lib/config.sh` in `03-install.sh`. Its responsibilities are:

- Scan removable block devices (those not in `lsblk` with `TYPE=disk` and not the install target) for a file at `/age/key.age`.
- If found, prompt for the age key passphrase and decrypt the key to a ramfs/tmpfs path.
- Discover all `users/*/secrets.json` and `hosts/*/secrets.json` files that exist in the repo.
- Decrypt each with `sops --decrypt` using `SOPS_AGE_KEY_FILE` pointing to the tmpfs key.
- Write the paths to each decrypted secrets tmpfs file into `install-state.json` (e.g. `secrets.users.<name>` and `secrets.host`).
- If no age key device is found and no secrets files exist, exit cleanly with a notice and skip all secrets handling.
- After the chroot phase exits, derive the machine age public key from `/mnt/etc/ssh/ssh_host_ed25519_key.pub` via `ssh-to-age` and print it alongside the `sops updatekeys` command.
- Clear the tmpfs unconditionally (success or failure) once derivation is complete.

### Modified: User Creation

`lib/chroot/create-user.sh` reads the per-user decrypted secrets path from `install-state.json`. If present, it reads `password` from the JSON and uses it instead of the hardcoded `12345` default. It also reads `ssh_identity_private_key` and `ssh_identity_key_type`, writes the private key to `~/.ssh/id_<type>` with permissions `600`, derives the public key with `ssh-keygen -y`, and writes it to `~/.ssh/id_<type>.pub`.

### Modified: Root Password

`lib/chroot/password.sh` reads the host decrypted secrets path from `install-state.json`. If present and `root_password` is set, it uses that value. Otherwise it falls back to the existing interactive prompt behaviour.

### New: SOPS Runtime Service (system program)

`.os/programs/security/sops/install.sh` installs the `sops` package, derives and stores the Machine Age Key at `/etc/secrets/age/keys.txt` from the SSH host key, and installs a systemd service unit that runs at `sysinit.target`. The service mounts a tmpfs at `/run/secrets/`, decrypts all SOPS files referenced in its configuration to that mount, and sets declared ownership and permissions. Programs reference `/run/secrets/<name>` paths.

### Secrets File Schemas

Per-user (`users/<name>/secrets.json`, SOPS-encrypted):
```json
{
  "password": "real-password",
  "ssh_identity_private_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n...",
  "ssh_identity_key_type": "ed25519"
}
```
`ssh_identity_key_type` accepts `ed25519`, `rsa`, or `ecdsa`; defaults to `ed25519` if absent.

Per-host (`hosts/<hostname>/secrets.json`, SOPS-encrypted):
```json
{
  "root_password": "real-root-password"
}
```

### `.sops.yaml`

Created at the repo root. Declares the operator's personal age public key as recipient for all secrets files. After first machine install, the operator adds the machine's age public key and runs `sops updatekeys`.

```yaml
creation_rules:
  - path_regex: \.os/(users|hosts)/.*secrets\.json$
    age: "age1..."
```

### install-state.json Threading

The Secrets Module writes keys like `secrets.users.<name>` (path to decrypted user secrets tmpfs file) and `secrets.host` (path to decrypted host secrets tmpfs file) into `install-state.json`. Chroot scripts read these via the existing `load-state.sh` mechanism — no new state-passing mechanism needed.

### Optionality

Every secrets-consuming path checks for the presence of its `install-state.json` key before reading. Absence means fall back to existing behaviour. The Secrets Module itself only activates if a key device is found or secrets files exist.

## Testing Decisions

Good tests assert external behaviour observed through the module's public interface (functions and their stdout/exit codes), not internal helpers or implementation order.

### Modules to test

**`lib/secrets.sh`**
- Key device not present + no secrets files → exits 0, no tmpfs created, install continues
- Key device found, wrong passphrase → exits non-zero with a clear error
- Key device found, correct passphrase, no secrets files → exits 0, no tmpfs entries written to install-state
- Key device found, correct passphrase, secrets files present → tmpfs populated, install-state.json contains correct paths
- Tmpfs cleared on exit regardless of success/failure

**`lib/chroot/create-user.sh`**
- No secrets path in install-state → password defaults to `12345`, no SSH key written
- Secrets path present, `password` field set → user created with that password
- Secrets path present, `ssh_identity_private_key` set, `ssh_identity_key_type: ed25519` → key written to `~/.ssh/id_ed25519` with mode `600`, public key derived to `~/.ssh/id_ed25519.pub`
- Secrets path present, `ssh_identity_key_type: rsa` → key written to `~/.ssh/id_rsa`

**`programs/security/sops/install.sh`**
- `ssh-to-age` derivation from a fixture SSH host key produces a valid age public key
- Generated systemd unit file passes `systemd-analyze verify`

### Prior art

Use the same BATS pattern as `tests/configs.bats`: `setup()` creates a temp dir, exports `OS_DIR`, sources the module under test; `teardown()` removes the temp dir. Write fixture key files and install-state fragments with a `write_fixture()` helper mirroring the existing `write_config()` helper.

## Out of Scope

- Runtime secret rotation without reinstalling
- SSH authorized_keys management (public keys for incoming SSH remain in `config.jsonc`)
- Multi-host secret sharing or key escrow
- Cloud KMS backends (AWS KMS, GCP KMS, Azure Key Vault)
- Automatic secret expiry or TTL
- Post-boot secret lifecycle management
- Secrets for system programs (only user creation and root password are in scope for this PRD)

## Further Notes

- ADR-0006 records the full decision trail including rejected alternatives (inline JSONC, single global secrets file, interactive-only, runtime-only).
- The `sops updatekeys` step is a one-time manual action per machine. The installer makes this as frictionless as possible by printing the exact command, but it cannot be automated without the machine already having network access and the operator's git credentials.
- `ssh-to-age` is a separate binary (`extra/ssh-to-age` on Arch). The `sops` program install script must ensure it is installed alongside `sops`.
- Secrets files should be added to `.gitignore` patterns for the decrypted tmpfs paths only; the SOPS-encrypted `secrets.json` files are safe to commit and should be tracked.
