# Prefactor: the secret screen carries its return target

Status: ready-for-agent

## Parent

.scratch/guided-encryption-editor/PRD.md
ADR: docs/adr/0059-guided-encryption-editor.md

## What to build

Make the inline masked secret screen record **where it should return to** when
it is opened, instead of two separate places re-deriving that from which secret
is being edited.

Today the answer is computed twice and must agree. The navigation module's
parent lookup branches on the secret's target — the disk passphrase goes back
to a category screen, everything else to the Users list — and the controller's
confirm path carries its own parallel conditional on target and category to
decide where to land after a passphrase is accepted. Neither knows about the
other.

Change the secret screen's nav constructor to take the screen it was opened
from, and have both the back path and the confirm path read that one field. The
callers that open the screen — root password, per-user password, disk passphrase
— each pass their own screen.

**This ticket changes no behaviour.** Every secret must still return exactly
where it returns today; the existing tests are the specification and must pass
untouched. Its whole value is that the next two tickets become one-line changes:
adding the Encryption Editor means passing a new screen value, and removing the
Users passphrase row means deleting a caller — rather than each editing two
co-dependent conditionals in different modules.

## Acceptance criteria

- [ ] The secret screen's nav carries the screen to return to
- [ ] The back path reads that field rather than branching on the target
- [ ] The confirm path reads the same field rather than its own conditional
- [ ] Root password capture still returns to the Users list
- [ ] Per-user password capture still returns to the Users list
- [ ] Disk passphrase capture still returns to the Disks category
- [ ] Cancelling a capture returns to the same screen as confirming it
- [ ] The type-twice mismatch path still restarts entry on the secret screen
- [ ] The nav module stays pure: JSON in, JSON out, no terminal reads
- [ ] No existing test is modified to accommodate this change

## Blocked by

None — can start immediately
