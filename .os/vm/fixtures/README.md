# VM smoke-test fixtures

**Throwaway.** Everything in this directory is a committed test
artifact — never use it for production secrets.

- `key.age` — passphrase-encrypted Age private key. Passphrase
  is the hard-coded string `test`. Type it at the live-CD
  prompt when the Secrets Module asks during `vm-secure.sh`.
- `regenerate.sh` — rotate the Test Age Key. Produces a fresh
  keypair, rewrites `key.age`, updates the test-rule recipient
  in `.sops.yaml`, and re-keys the committed
  `secrets.json` fixtures via `sops updatekeys`. Idempotent.

See `docs/adr/0019-committed-sops-fixtures-for-vm-smoke-tests.md`
for the trade-off rationale.
