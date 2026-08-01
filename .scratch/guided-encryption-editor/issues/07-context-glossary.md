# CONTEXT.md glossary: Encryption Editor

Status: done

## Parent

.scratch/guided-encryption-editor/PRD.md
ADR: docs/adr/0059-guided-encryption-editor.md

## What to build

Bring the domain glossary back in step with the code.

The glossary currently defines an **Encryption Password Row** and describes it
as a row on the Disks screen that joins a Proceed gate, blocking install while
the passphrase is unset and flagging the Disks category with a warning count.
That entry was already stale before this feature — the Proceed gate was removed
when every secret gained a default — and the row it names no longer exists.

Replace it with an **Encryption Editor** entry describing the surface as built:
one collapsed row on the Disks screen beneath the filesystem row, opening an
editor that holds the enablement toggle and the disk passphrase; the passphrase
row hidden while encryption is off but its value retained; enablement cycling in
place; and the entry rule that the passphrase must be at least eight characters
because ZFS requires it.

Also update the Guided Installer entry, which states that every secret defaults
to one shared value. Record the split: accounts keep the account default, the
disk passphrase uses an eight-character default, and note that the difference
exists because ZFS enforces a floor the account passwords have no equivalent of.

Keep the glossary a glossary. No file paths, no function names, no
implementation detail — terms and their meanings only.

## Acceptance criteria

- [ ] The Encryption Password Row entry is removed
- [ ] An Encryption Editor entry is added in its place
- [ ] The new entry describes the collapsed row and the editor it opens
- [ ] The new entry records the hidden-while-off, value-retained behaviour
- [ ] The new entry records the ≥8-character rule and names ZFS as the reason
- [ ] The Guided Installer entry records the split between the two defaults
- [ ] No entry mentions the removed Proceed gate as if it were current
- [ ] No entry references the Users screen as a disk passphrase override surface
- [ ] Entries contain no file paths, function names, or implementation detail
- [ ] All lines are at most 80 characters

## Blocked by

- .scratch/guided-encryption-editor/issues/05-remove-users-enc-row.md
