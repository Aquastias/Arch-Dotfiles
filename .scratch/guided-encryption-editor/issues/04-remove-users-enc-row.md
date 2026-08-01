# Remove the `disk encryption` row from the Users screen

Status: ready-for-agent

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

Order matters — this slice must land after the Encryption Editor, so there is
never a state with no way to override the passphrase.

The account rows are untouched, and this is worth asserting: they still report
the account default, not the disk default. That assertion guards the deliberate
split between the two defaults against a later single-constant refactor.

## Acceptance criteria

- [ ] The Users screen renders no `disk encryption` row when encryption is on
- [ ] The Users screen renders no `disk encryption` row when encryption is off
- [ ] Its enter handler is gone; no Users row routes to the passphrase capture
- [ ] The root password row still renders and still opens its capture
- [ ] Per-user password rows still render and still open their captures
- [ ] The root shell row and the user editor rows are unchanged
- [ ] Account rows report the account default, not the disk default
- [ ] The passphrase remains editable from the Encryption Editor
- [ ] A passphrase set before this change is still read at install time

## Blocked by

- .scratch/guided-encryption-editor/issues/03-encryption-editor.md
