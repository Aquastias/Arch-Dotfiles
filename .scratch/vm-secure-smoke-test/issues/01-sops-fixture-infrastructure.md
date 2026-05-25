Status: ready-for-agent

# Commit SOPS test fixtures + regeneration script

## Parent

`.scratch/vm-secure-smoke-test/PRD.md` (ADR 0019)

## What to build

End-state: `sops --decrypt hosts/vm/arch-secure/secrets.json`
and `sops --decrypt users/vm-test/secrets.json` both round-trip
using a key decrypted from `.os/vm/fixtures/key.age` with the
passphrase `test`. No installer wiring or VM script yet — this
slice lands the fixture infrastructure on its own.

Five artifacts land in this slice:

1. `.os/vm/fixtures/key.age` — a passphrase-encrypted Age key,
   passphrase `test`. The plaintext private key never lives in
   the repo.
2. `.os/vm/fixtures/regenerate.sh` — idempotent rotation
   script. Generates a fresh Age keypair, writes the
   passphrase-encrypted private key to `key.age`, writes the
   public key into `.sops.yaml`'s test-creation rule
   recipient, and runs `sops updatekeys --yes` against the
   two committed `secrets.json` paths so they re-key without
   their plaintext changing. Hardcodes the passphrase `test`
   for both reading the old key and writing the new one.
3. `.os/vm/fixtures/README.md` — one short paragraph stating
   that the fixtures are throwaway, naming the passphrase
   `test`, and pointing at ADR 0019 and `regenerate.sh`.
4. `hosts/vm/arch-secure/secrets.json` — SOPS-encrypted under
   the Test Age Key. Contains `root_password` (any throwaway
   value such as `vmtest`).
5. `users/vm-test/secrets.json` — SOPS-encrypted under the
   Test Age Key. Contains `password` (throwaway, e.g.
   `vmtest`), `ssh_identity_private_key` (a freshly-generated
   throwaway ed25519 private key in OpenSSH format), and
   `ssh_identity_key_type` set to `"ed25519"`.

`.sops.yaml` gains a second entry under `creation_rules`. The
existing placeholder rule (`age1REPLACE_WITH_OPERATOR_PUBLIC_KEY`)
stays untouched and remains first. The new entry's
`path_regex` matches *only* the two test paths above; its
`age:` value is the Test Age Key's public half.

Initial seeding workflow (one-time, performed by the
implementing agent): generate the keypair → encrypt the
private key with `age -p` and passphrase `test` → write
`.sops.yaml`'s new rule with the public key → hand-create
plaintext `secrets.json` files at the two paths → run
`sops -e -i` on each. `regenerate.sh` then takes over for
all future rotations.

A bats test under `.os/tests/` exercises `regenerate.sh` in a
temporary working copy of the four fixture files. It asserts
round-trip: after running `regenerate.sh`, decrypting `key.age`
with passphrase `test` yields a private key whose public half
matches `.sops.yaml`'s test recipient, and both `secrets.json`
files still decrypt successfully with that key.

## Acceptance criteria

- [ ] `.os/vm/fixtures/key.age` exists and is a valid
      passphrase-encrypted Age key (passphrase `test`).
- [ ] `.os/vm/fixtures/regenerate.sh` exists, is executable
      (`chmod +x`), uses `set -Eeuo pipefail`, and shellcheck
      passes.
- [ ] `.os/vm/fixtures/README.md` exists, names the
      passphrase `test`, links to ADR 0019, and explicitly
      labels the fixtures throwaway.
- [ ] `hosts/vm/arch-secure/secrets.json` exists and is a
      SOPS-encrypted JSON document containing
      `root_password`.
- [ ] `users/vm-test/secrets.json` exists and is a
      SOPS-encrypted JSON document containing `password`,
      `ssh_identity_private_key`, and `ssh_identity_key_type:
      "ed25519"`.
- [ ] `.sops.yaml` contains a second `creation_rules` entry
      whose `path_regex` matches *only*
      `hosts/vm/arch-secure/secrets.json` and
      `users/vm-test/secrets.json`, with `age:` set to the
      Test Age Key's public half.
- [ ] The original placeholder rule
      (`age1REPLACE_WITH_OPERATOR_PUBLIC_KEY`) in
      `.sops.yaml` is byte-identical to before this slice.
- [ ] Running `bash .os/vm/fixtures/regenerate.sh` in a
      clean clone is idempotent — it produces a new keypair
      but leaves both `secrets.json` files still decryptable
      with the regenerated key.
- [ ] A bats test exists that runs `regenerate.sh` against
      a temp copy of the four fixture files and asserts:
      (a) `key.age` decrypts with passphrase `test` to a
      valid Age private key, (b) that private key's public
      half matches `.sops.yaml`'s test-rule recipient,
      (c) both `secrets.json` files decrypt successfully
      with the regenerated key, (d) a second invocation
      produces a different keypair but the secrets remain
      decryptable.
- [ ] The bats test never mutates the committed fixtures in
      `.os/vm/fixtures/` or under `hosts/` / `users/`.
- [ ] Full bats suite passes; shellcheck passes on every
      changed shell file.
- [ ] Single commit, conventional-commit style, capitalized
      after the prefix.

## Blocked by

None - can start immediately.
