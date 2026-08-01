# Collapsed `Encryption ▸` row + the Encryption Editor

Status: done

## Parent

.scratch/guided-encryption-editor/PRD.md
ADR: docs/adr/0059-guided-encryption-editor.md

## What to build

Replace the Disks screen's two encryption rows — the enablement toggle and the
passphrase row beneath it — with a single `Encryption ▸` row that opens a new
**Encryption Editor**.

### The collapsed row

Keep the row in its existing slot beneath the filesystem row; the filesystem is
what derives the cipher. Its summary text comes from a label helper alongside
the existing layout and swap label helpers — effective config and secret source
tag in, one line of text out, called and asserted directly the way the swap
label already is:

```
Encryption ▸ on · default 12345678
Encryption ▸ on · custom              ●
Encryption ▸ on · from age
Encryption ▸ off
```

Spelling the literal default keeps a weak passphrase visible without drilling.
The override dot follows the existing rule: shown when enablement differs from
the baseline. The off state carries no source tag — the passphrase is inert.

The enablement field stays in the menu field table so it keeps driving the
override dot and the Disks category summary; only its row render is
special-cased, the same way the passphrase row already was.

### The Editor

A new navigation screen with its own nav constructor, prompt and footer,
modelled on the swap sub-editor — including its conditional collapse:

```
enabled: false          enabled: true
← Back                  password: default 12345678
                        ← Back
```

The passphrase row is hidden while encryption is off because it configures
nothing in that state; the stored value is retained regardless, so toggling back
on shows it again. `enabled` cycles in place through the existing cycle helper
rather than drilling to a true/false list — nesting the old values-screen route
would put a boolean three levels deep. Setting a passphrase does **not** flip
enablement: the toggle stays the single source of truth for whether the disk is
encrypted.

The passphrase row opens the existing inline-masked, type-twice capture with its
≥8-character entry rule. Because the secret screen now carries its return
target, opening it from here is a matter of passing this screen — no conditional
in the back or confirm paths.

Rendered output stays limited to narrow geometric unicode. Do not introduce
emoji — they are double-width and break alignment in the persistent fzf.

## Acceptance criteria

- [ ] Disks shows one `Encryption ▸` row in the slot beneath filesystem
- [ ] The row's four summary states render correctly
- [ ] The row shows the override dot when enablement differs from the baseline
- [ ] The label helper is called and asserted directly, without a screen render
- [ ] The separate passphrase row no longer appears on the Disks screen
- [ ] Enter on the row opens the Encryption Editor
- [ ] The Editor shows only the enablement row and Back when encryption is off
- [ ] The Editor shows enablement, passphrase and Back when encryption is on
- [ ] Enter on the enablement row flips it and stays on the Editor
- [ ] Enter on the passphrase row opens the inline-masked capture
- [ ] A passphrase under 8 characters is refused inline with a notice
- [ ] Confirming a passphrase returns to the Encryption Editor
- [ ] Cancelling a passphrase also returns to the Encryption Editor
- [ ] Setting a passphrase leaves enablement unchanged
- [ ] A stored passphrase survives an off→on round-trip and reads as custom
- [ ] The Editor's footer and prompt match the other sub-editors
- [ ] Esc from the Editor returns to the Disks screen
- [ ] No emoji appear in any rendered row
- [ ] The replay seam still drives enablement unchanged

## Blocked by

- .scratch/guided-encryption-editor/issues/01-secret-return-target.md
- .scratch/guided-encryption-editor/issues/03-manifest-8char-default.md
