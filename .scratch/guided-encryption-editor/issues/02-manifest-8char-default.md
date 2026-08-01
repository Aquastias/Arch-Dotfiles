# Guided Secrets Manifest defaults to the 8-char passphrase

Status: ready-for-agent

## Parent

.scratch/guided-encryption-editor/PRD.md
ADR: docs/adr/0059-guided-encryption-editor.md

## What to build

Make the Guided Installer's default disk passphrase actually installable.

The Secrets Manifest fill currently defaults every unset secret — accounts and
the disk passphrase alike — to the five-character account default. ZFS rejects a
passphrase that short, so a guided encrypted install where the operator does not
override the passphrase dies at pool creation, after the disk wipe has already
been confirmed. Both committed personal Host Profiles are encrypted, so this is
the one-select path failing.

Change the fill so the **disk passphrase** defaults to the shared constant from
slice 01 while **accounts keep their existing default**. The asymmetry is
deliberate and must survive refactoring: only the disk passphrase has a length
floor, and it exists because ZFS imposes it.

The secret source tag helper — which reports whether a secret is an operator
override, an age-decrypted value, or a default — gains a role-dependent default
branch so it names the right value per secret. Its override and age branches are
unchanged.

At this point the existing Disks and Users rows still work; this slice changes
only what an untouched passphrase resolves to. It is verifiable on its own: a
guided encrypted install with no override now completes.

## Acceptance criteria

- [ ] An unset disk passphrase fills from the shared 8-character constant
- [ ] Unset account passwords still fill with the existing account default
- [ ] The filled disk passphrase satisfies ZFS's ≥8-character floor
- [ ] The source tag reports the disk default value for the disk passphrase
- [ ] The source tag reports the account default value for root and users
- [ ] An operator override still reports as a custom value, not a default
- [ ] An age-decrypted secret still reports as coming from age
- [ ] Neither default enters Config State, Save profile, or Export config
- [ ] Proceed remains ungated on every secret
- [ ] A guided encrypted install with no override reaches pool creation with a
      passphrase ZFS accepts

## Blocked by

- .scratch/guided-encryption-editor/issues/01-passphrase-constant-unattended.md
