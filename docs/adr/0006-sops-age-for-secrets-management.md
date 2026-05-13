# SOPS + age for secrets management

Secrets (initial user/root passwords, SSH identity private keys) are stored as SOPS-encrypted JSON files co-located with their config: `users/<name>/secrets.json` and `hosts/<hostname>/secrets.json`. Encryption uses age. At install time, the operator provides a passphrase-protected age key file (scanned from removable media at `/age/key.age`); `lib/secrets.sh` prompts for the passphrase, decrypts the key to a tmpfs, then decrypts all secrets files and threads their tmpfs paths through `install-state.json` to chroot scripts. SOPS is optional — if no `secrets.json` exists for a user or host, the installer falls back to its previous behaviour (hardcoded `12345` user password, interactive root password prompt). At runtime, a systemd service (`programs/security/sops/install.sh`) decrypts secrets to `/run/secrets/` on every boot using a Machine Age Key stored at `/etc/secrets/age/keys.txt`.

## Status

proposed

## Considered Options

**Inline in config.jsonc** — ruled out: SOPS does not support JSONC (comments break the parser).

**Single global secrets file** — ruled out: breaks the per-user/per-host co-location pattern established by ADR-0004.

**Interactive-only (no stored secrets)** — ruled out: SSH identity private keys cannot be typed interactively; runtime services need secrets on every boot without operator presence.

**Runtime-only activation** — ruled out: violates ADR-0003 (all installation happens during live CD).

## Consequences

- Machine Age Key is derived from `ssh_host_ed25519_key` via `ssh-to-age` at install time. After chroot exits, the installer outputs the machine's age public key and prompts the operator to run `sops updatekeys` to add it as a recipient and re-encrypt secrets before runtime decryption works.
- `.sops.yaml` at repo root must list the operator's personal age public key as recipient so secrets can be created and rotated without the machine present.
- SSH identity key type is configurable per user (`ssh_identity_key_type`: `ed25519`, `rsa`, `ecdsa`; defaults to `ed25519`). The installer writes the private key to `~/.ssh/id_<type>`.
- SOPS is fully optional. Installing without any `secrets.json` files produces a working system with default credentials.
