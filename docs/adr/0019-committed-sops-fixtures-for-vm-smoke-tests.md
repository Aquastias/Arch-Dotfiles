# ADR 0019: Committed SOPS test fixtures for VM smoke tests

## Status
Accepted

## Context
The persistent VM scripts under `.os/vm/` (`vm-kde.sh`,
`vm-hyprland.sh`, `vm-kde-hyprland.sh`) inline an
`INSTALL_CONFIG_CONTENT` with `encryption: false`, no
`options.impermanence` block, and no `options.age_key_url`. The
Secrets Module (`lib/secrets.sh`), the Impermanence install
path (Persist Dataset, Rollback Hook, Blank Snapshot), and ZFS
native encryption are therefore unexercised by these scripts.

The unattended side (`.os/tests/vm/`) covers *some* of the
combinations (`testing-single-disk-impermanent-kde-sops.sh`,
`testing-single-disk-impermanent-kde-encrypted.sh`), but:

- no script covers SOPS + impermanence + encryption together;
- both SOPS-touching scripts require operator-supplied
  `DOTFILES_REPO_URL` + `AGE_KEY_URL` — no committed fixtures
  exist anywhere in the repo;
- `.sops.yaml` ships with `age1REPLACE_WITH_OPERATOR_PUBLIC_KEY`
  as its sole recipient, so no `secrets.json` file in the repo
  can be created or decrypted out of the box.

Adding a `.os/vm/` script that exercises the combined path
requires real (encrypted) inputs: an Operator Age Key the
installer can fetch, a passphrase to decrypt it, and SOPS-
encrypted `secrets.json` files matching the test host and user.

## Decision
Commit test fixtures into the repo:

- `.os/vm/fixtures/key.age` — passphrase-encrypted Age key,
  passphrase `test`. Operator types `test` at the live-CD
  prompt when the Secrets Module asks.
- `hosts/vm/arch-secure/secrets.json` — SOPS-encrypted with the
  fixture key.
- `users/vm-test/secrets.json` — SOPS-encrypted with the same
  fixture key.
- `.sops.yaml` grows a second `creation_rules` entry scoped to
  the two test paths above, listing only the fixture public
  key. The original placeholder rule for
  `(users|hosts)/[^/]+/secrets.json` stays untouched.

The VM harness copies `key.age` into `${CACHE_DIR}` alongside
the rendered installer script; the existing python HTTP server
serves it at `http://192.168.122.1:9876/key.age`, and the
inlined `INSTALL_CONFIG_CONTENT` points `options.age_key_url`
there.

## Considered alternatives
- **Generate on-the-fly.** The VM script generates a fresh Age
  key + secrets at runtime, encrypts them, hands them off, then
  discards. Rejected: each run produces different ciphertext, so
  a "what changed?" debugging session can't reason from
  `git diff` against a known fixture; also moves significant
  SOPS scaffolding into the harness for a one-shot use.
- **Operator-supplied URLs** (the pattern `.os/tests/vm/`
  already uses). Rejected for `.os/vm/`: the persistent VMs are
  framed as one-command smoke tests (`bash vm/vm-kde.sh`);
  requiring the operator to stand up a separate dotfiles fork
  plus host an Age key URL inverts that.
- **Reuse an existing user/host.** Rejected adding
  `secrets.json` to `users/aquastias/`: every real host config
  that lists `aquastias` would then start consuming that
  fixture file at install time, changing the behaviour of
  production installs. A dedicated `users/vm-test/` listed only
  in `hosts/vm/arch-secure/config.jsonc` keeps blast radius
  contained.

## Consequences
- A passphrase-encrypted `.age` file lives in the repo with a
  publicly-known passphrase. Anyone reading the repo can
  decrypt the test secrets. Acceptable because the test secrets
  *are* test secrets — the user `vm-test`, the hostname
  `arch-secure`, and all credentials are throwaway values; no
  production system uses them.
- The fixture pattern under `.os/vm/` is not backported to
  `.os/tests/vm/`. Those scripts retain their external-URL
  contract. A future ADR may revisit if duplication grows
  painful.
- `.sops.yaml` becomes the canonical place to find both the
  operator-recipient slot and the test-recipient. Operators
  generating their own key still edit the first rule (the
  placeholder); they leave the second rule alone.
- The combined-path coverage gap noted in Context closes for
  one disk layout (mirror, 2 disks) and one feature combo
  (sops + impermanence + encryption, no desktop). Coverage of
  other axes (single-disk encryption, raidz, desktop +
  impermanence) remains in `.os/tests/vm/`.
