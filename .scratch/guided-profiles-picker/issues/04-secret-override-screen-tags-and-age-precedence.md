# Secret override screen: tags + `Disk encryption` + age precedence

Status: done

## Parent

.scratch/guided-profiles-picker/PRD.md
ADR: docs/adr/0055-guided-profiles-picker-and-default-secret-posture.md

## What to build

The operator-facing override surface for the default-`12345` posture. The Users
screen lists **root · each user · `Disk encryption`**, each tagged with its
current source: **`default 12345`** / **`custom`** (operator-typed) /
**`from age`** (decrypted committed secret). Enter opens the existing
inline-masked secret screen (ADR 0051) to override any single one; overriding is
optional. When an age key resolves (via `options.age_key_url` or a local
`/etc/secrets` key, ADR 0025), the committed encrypted secret decrypts and takes
**precedence** over the default, shown `from age`. Override scope is passwords +
the encryption passphrase only — SSH identities stay on their existing path.

## Acceptance criteria

- [x] The Users screen lists root, each user, and a `Disk encryption` entry
- [x] Each entry shows a tag: `default 12345`, `custom`, or `from age`
- [x] Enter opens the inline-masked secret screen; a confirmed value flips the tag
      to `custom` and takes effect at install
- [x] An age-resolved secret shows `from age` and takes precedence over `12345`
- [x] An operator override takes precedence over an age-resolved value for that
      install
- [x] SSH identities are not editable from this screen (unchanged path)
- [x] Precedence/tagging behaviour covered by bats over the menu/secrets model
      (`guided-menu.bats` / `guided-secrets.bats` prior art); inline-masked screen
      smoke-only

## Blocked by

- 03 — Default-`12345` posture: manifest + Proceed-gate removal

## Comments

- 2026-09-27 audit: f8af150. Later: the Users-screen Disk-encryption row moved
  into the Encryption Editor (ADR 0059).
