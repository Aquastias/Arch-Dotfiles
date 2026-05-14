Status: done

# SOPS Runtime Service + machine key lifecycle

## Parent

`.scratch/sops-secrets-management/PRD.md`

## What to build

Deliver the full runtime secrets lifecycle: a system program that derives the Machine Age Key, installs a boot-time decryption service, and triggers the post-install `sops updatekeys` workflow.

### Program: `.os/programs/security/sops/`

`install.sh` runs inside the chroot as a system program and does the following:

1. Install `sops` and `ssh-to-age` packages via pacman.
2. Derive the Machine Age Key from `/etc/ssh/ssh_host_ed25519_key.pub` using `ssh-to-age`. Write the private age key to `/etc/secrets/age/keys.txt` with permissions `600` owned by root.
3. Install a systemd service that runs at `sysinit.target` (before user services). On every boot the service:
   - Mounts a tmpfs at `/run/secrets/`
   - Decrypts all SOPS-encrypted secret files using the Machine Age Key at `/etc/secrets/age/keys.txt`
   - Sets declared ownership and permissions on each decrypted file
4. Enable the service.

`config.jsonc` marks the program as `system: true`.

### Post-install guidance (lib/secrets.sh)

After the chroot phase exits and the Machine Age Key has been written, `lib/secrets.sh` reads the machine's age public key from `/mnt/etc/secrets/age/keys.txt` (using `age-keygen -y` or parsing the key file) and prints:

```
==> Machine age public key: age1...
==> Run: sops updatekeys .os/users/*/secrets.json .os/hosts/*/secrets.json
==> Then update .sops.yaml to include this key and commit.
```

### Host core opt-in

Add `sops` to `.os/hosts/core/config.jsonc` system programs so it is installed on all hosts.

## Acceptance criteria

- [ ] `sops` and `ssh-to-age` are installed by the program's `install.sh`
- [ ] `/etc/secrets/age/keys.txt` exists after program install, is owned by root, has permissions `600`
- [ ] The age key in `/etc/secrets/age/keys.txt` is derivable from the machine's `ssh_host_ed25519_key` (deterministic)
- [ ] Systemd service unit passes `systemd-analyze verify`
- [ ] Service is enabled and runs at `sysinit.target`
- [ ] After chroot exits, installer prints the machine age public key and the exact `sops updatekeys` command
- [ ] `sops` appears in `.os/hosts/core/config.jsonc` system programs
- [ ] BATS test: `ssh-to-age` derivation from a fixture SSH host key produces a valid age public key
- [ ] BATS test: generated systemd unit file passes `systemd-analyze verify`

## Blocked by

- `.scratch/sops-secrets-management/issues/01-secrets-module.md`
