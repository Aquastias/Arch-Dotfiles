# Remove the `disk encryption` row from the Users screen

Status: done

## Parent

.scratch/guided-encryption-editor/PRD.md
ADR: docs/adr/0059-guided-encryption-editor.md

## What to build

Close the second door onto the disk passphrase.

The Users screen carries a `disk encryption` row that opens the same masked
capture and writes the same Secrets Manifest key as the Encryption Editor. With
the Editor in place, that row is a duplicate editor for one value. Remove the
row and its enter handler.

This narrows the "single override surface" idea to **accounts**: the Users
screen becomes strictly root plus per-user credentials and shells, and the disk
passphrase lives beside the toggle that gives it meaning.

Because the secret screen now carries its own return target, this is a deletion
rather than an edit to shared branching — nothing else has to change to keep the
remaining captures returning where they should.

Order matters: this ticket lands after the Encryption Editor, so there is never
a state with no way to override the passphrase.

The account rows are untouched, and this is worth asserting: they still report
the account default, not the disk default. That assertion guards the deliberate
split between the two defaults against a later single-constant refactor.

## Acceptance criteria

- [x] The Users screen renders no `disk encryption` row when encryption is on
- [x] The Users screen renders no `disk encryption` row when encryption is off
- [x] Its enter handler is gone; no Users row routes to the passphrase capture
- [x] The root password row still renders and still opens its capture
- [x] Per-user password rows still render and still open their captures
- [x] The root shell row and the user editor rows are unchanged
- [x] Account rows report the account default, not the disk default
- [x] The passphrase remains editable from the Encryption Editor
- [x] A passphrase set before this change is still read at install time
- [x] No dead return-target branch is left behind for the disk passphrase

## Blocked by

- .scratch/guided-encryption-editor/issues/04-encryption-editor.md

## Comments

- 2026-09-27 audit: ca227d8.
