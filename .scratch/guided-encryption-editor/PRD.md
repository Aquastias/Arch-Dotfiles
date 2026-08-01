# Guided Encryption Editor + 8-char default disk passphrase

Status: ready-for-agent

ADR: docs/adr/0059-guided-encryption-editor.md

## Problem Statement

The Guided Installer scatters one decision — "is this disk encrypted, and with
what passphrase?" — across three rows on two screens. **Disks** has an
`encryption` toggle and, beneath it, an `encryption password` row. The **Users**
screen has a third row, `disk encryption`, that edits the exact same secret. Two
of those three are doors into one value, and they disagree about how to describe
it: Disks renders `(not set) ⚠` while Users renders `default 12345`.

Worse, the thing they configure cannot install. Every unset secret defaults to
`12345`, but ZFS `keyformat=passphrase` rejects anything under 8 characters at
pool creation. So a guided encrypted install where I do not override the
passphrase dies partway through, at `zpool create`, after I have already
confirmed the disk wipe. Both of my committed Host Profiles (`desktop`,
`laptop`) are encrypted, so the one-select install is precisely the path
that fails.

The same gap bites from the other direction outside the menu.
`install.sh --profile desktop -y` promises to bypass every interactive
confirmation, then blocks forever on a tty passphrase prompt, because nothing
non-guided supplies a passphrase.

None of this was caught, because the VM harness presets
`INSTALL_ENC_PASSPHRASE` for every encrypted guided run — the highest-precedence
tier — so no test has ever executed the path the menu actually produces.

## Solution

The three surfaces collapse into one **Encryption Editor**, reached from one
`Encryption ▸` row that stays where `encryption` already sits on the Disks
screen. The row summarises both facts at a glance:

```
Encryption ▸ on · default 12345678
Encryption ▸ on · custom              ●
Encryption ▸ on · from age
Encryption ▸ off
```

Enter opens an editor that expands and collapses the way the swap sub-editor
already does — when encryption is off it shows only the toggle, because a
passphrase configures nothing in that state:

```
enabled: false          enabled: true
← Back                  password: default 12345678
                        ← Back
```

The default disk passphrase becomes `12345678`, long enough for ZFS to accept.
Account passwords keep `12345` — nothing enforces a floor on them. That default
also becomes available to the back end under `--unattended`, so
`install.sh --profile desktop -y` completes instead of hanging, while an
interactive profile install still prompts rather than silently encrypting a disk
with a value the operator was never shown.

The `disk encryption` row leaves the Users screen. One secret, one door.

## User Stories

1. As an operator, I want one `Encryption ▸` row on the Disks screen, so that
   the encryption decision is in one place instead of three.
2. As an operator, I want that row to sit beneath `filesystem`, so that it stays
   where I already expect it and beside the choice that derives its cipher.
3. As an operator, I want the collapsed row to tell me whether encryption is on,
   so that I can read the state without drilling in.
4. As an operator, I want the collapsed row to tell me where the passphrase came
   from, so that I know whether I am about to install a default.
5. As an operator, I want the literal `12345678` spelled on that row, so that a
   weak default is visible without hunting for it.
6. As an operator, I want an override dot on the row when I have changed
   encryption from the baseline, so that it matches every other field.
7. As an operator, I want Enter on the row to open an Encryption Editor, so that
   the toggle and the passphrase are edited together.
8. As an operator, I want the Editor to show only `enabled` when encryption is
   off, so that I am not offered a field that does nothing.
9. As an operator, I want the Editor to show `enabled` and `password` when
   encryption is on, so that both settings are reachable in one screen.
10. As an operator, I want Enter on `enabled` to flip it in place, so that a
    boolean does not cost me a third level of navigation.
11. As an operator, I want to stay on the Editor after toggling, so that I can
    set the passphrase immediately afterwards.
12. As an operator, I want Enter on `password` to open the same inline-masked,
    type-twice screen the account passwords use, so that the interaction is
    familiar.
13. As an operator, I want confirming a passphrase to return me to the Editor,
    so that I land where I started rather than on a different screen.
14. As an operator, I want a passphrase shorter than 8 characters refused inline
    with a notice, so that I correct it in the menu rather than at `zpool
    create`.
15. As an operator, I want my typed passphrase retained when I toggle encryption
    off, so that a fat-finger toggle does not discard a value I typed twice.
16. As an operator, I want that retained passphrase to reappear as `custom` when
    I toggle back on, so that I can see it survived.
17. As an operator, I want setting a passphrase to leave the toggle alone, so
    that I can never arrive at an encrypted install I did not explicitly choose.
18. As an operator, I want the passphrase to default to `12345678`, so that an
    encrypted guided install actually completes without an override.
19. As an operator, I want my account passwords to keep defaulting to `12345`,
    so that this change does not silently alter my login credentials.
20. As an operator, I want the `disk encryption` row gone from the Users screen,
    so that there is only one place to edit the passphrase.
21. As an operator, I want the Users screen to still show root and per-user
    password rows unchanged, so that account overrides work exactly as before.
22. As an operator, I want the Editor's footer to read `Enter edit/toggle   Esc
    back`, so that the controls match the other sub-editors.
23. As an operator, I want `Esc` from the Editor to return to Disks, so that
    navigation is reversible.
24. As an operator, I want `install.sh --profile desktop -y` to install without
    stopping, so that `--unattended` means what it says.
25. As an operator running an interactive profile install, I want to still be
    prompted for a passphrase, so that my disk is never encrypted with a default
    I was never asked about.
26. As an operator, I want `INSTALL_ENC_PASSPHRASE` to keep overriding
    everything, so that existing scripted and VM installs are unaffected.
27. As an operator, I want the passphrase I set in the menu to beat the
    `--unattended` default, so that the menu remains authoritative.
28. As an operator, I want no plaintext passphrase written by Save profile or
    Export config, so that no secret reaches a committed file.
29. As an operator, I want Proceed never blocked on the passphrase, so that the
    one-select install stays one select.
30. As a maintainer, I want the new precedence tier covered by the existing
    precedence tests, so that the whole ladder stays proven at one seam.
31. As a maintainer, I want the collapsed row's text behind the same kind of
    label helper the swap row uses, so that its states are testable without fzf.
32. As a maintainer, I want the default defined once as a named constant, so
    that the ZFS reason for its length lives beside its definition.
33. As a maintainer, I want the guided VM fixture to stop presetting
    `INSTALL_ENC_PASSPHRASE`, so the manifest reaches a real `zpool create`.
34. As a maintainer, I want non-guided VM fixtures to keep their preset, so that
    flows with no Secrets Manifest still install.
35. As a maintainer, I want the replay seam untouched, so that the VM Harness
    drives the menu exactly as before.

## Implementation Decisions

### Scope of the merge

All three surfaces merge. The Disks `encryption` toggle and `encryption
password` row become one `Encryption ▸` row opening the Encryption Editor; the
Users screen's `disk encryption` row is deleted along with its enter handler.
ADR 0055's "single override surface" narrows to accounts only.

### Row placement and rendering

`options.encryption` stays in the menu field table. It still drives the override
dot and the Disks category summary; only its row *render* is special-cased,
exactly as the passphrase row already was. This keeps the row in its current
slot beneath `filesystem` rather than promoting it to the hand-written block
with layout, root disk and swap.

### Precedence ladder gains a tier in place

The passphrase ladder is **not** extracted. It is already driven end-to-end by
an existing test block, including the fall-through to the tty prompt, so pulling
a pure resolver out of it would duplicate coverage rather than create it. The
ladder gains one tier where it stands:

1. `INSTALL_ENC_PASSPHRASE` — test/VM preset
2. Secrets Manifest (`enc_passphrase`)
3. `INSTALL_UNATTENDED=1` → the default constant — **new**
4. interactive tty prompt (still enforcing ≥8)

Tier 3 is deliberately gated on unattended rather than unconditional. An
interactive profile install must still prompt. This mirrors how the chroot layer
already gates root's `12345` default on the same variable.

### Collapsed row label helper

A label helper takes the effective config and the secret source tag and returns
the row's summary text, alongside the existing layout and swap label helpers —
matching how the swap row is already structured and already tested. Four states:
`off`, `on · default <value>`, `on · custom`, `on · from age`.

### Editor screen

A new navigation screen with its own nav constructor, prompt and footer,
modelled on the swap sub-editor. Its render collapses to a single `enabled` row
when encryption is off and expands to `enabled` plus `password` when on — the
same conditional shape the swap editor uses. The `enabled` row cycles in place
through the existing cycle helper rather than drilling to a values screen.

### Secret source tag

The tag helper's default branch becomes role-dependent: accounts report the
account default, the disk passphrase reports the disk default. The age-decrypted
and operator-override branches are unchanged.

### Default constant

One shared constant holds `12345678`, guarded so that re-sourcing cannot abort
on a readonly reassignment. It is consumed by the manifest fill, the tag helper
and the ladder. The comment beside it records the ZFS `keyformat=passphrase`
minimum as the reason for its length.

### Glyph vocabulary

Rendered output stays limited to narrow geometric unicode. The lock emoji ADR
0055 described for the age tag was never implemented and is not adopted; emoji
are double-width and break alignment in the persistent fzf.

### VM harness

The guided user-data renderer stops exporting `INSTALL_ENC_PASSPHRASE`. This
affects only the single fixture that is both guided and encrypted, which is
install-only, so no boot-time passphrase entry is involved. Non-guided fixtures
are untouched.

### Delivery

Three commits: the unattended back-end fix and the shared constant first, since
they stand alone and the constant must exist before the menu consumes it; then
the Encryption Editor; then the documentation.

## Testing Decisions

A good test here asserts **rendered screen content and resolved values** — what
the operator sees and what the installer would use — never internal call
sequences or helper invocation counts. Package-style `$CALLS` assertions are
explicitly not the tool for this feature: every claim worth making is about a
string on screen or a variable after resolution.

Four seams, three of them already in the codebase. No new seam kind is
introduced.

### Seam 1 — the passphrase precedence ladder (existing)

Prior art: the existing precedence block in the ZFS pools suite, which already
covers the disabled short-circuit, the preset tier, the manifest tier, and the
fall-through to the prompt (stubbing the tty reader so the last case is
observable without a terminal).

Extend that block rather than starting a new one: the unattended tier resolves
to the 8-character constant; the manifest still beats it; the preset still beats
both; an interactive run with nothing set still reaches the prompt. One
assertion pins the default against ZFS's ≥8 floor — the assertion whose absence
let the original bug ship.

### Seam 2 — the guided controller render/enter pair (existing)

Prior art: the guided controller suite, which drives the controller's render and
enter entry points and asserts on the emitted lines. Everything the operator
touches goes through here:

- the Editor's two collapse states
- `enabled` cycling in place without changing screen
- a stored passphrase surviving an off→on round-trip and reading `custom`
- setting a passphrase leaving the toggle false
- the passphrase row routing to the masked capture, and returning to the Editor
- the Users screen no longer rendering a `disk encryption` row, while root and
  per-user rows still render and still report the account default

That last assertion guards the deliberate split between the two defaults against
a later single-constant refactor.

### Seam 3 — the Secrets Manifest fill (existing)

Prior art: the guided secrets suites, which assert the manifest's contents after
a fill. Cover that an unset disk passphrase fills from the 8-character constant
while unset accounts keep the account default, and that neither reaches Config
State, Save or Export.

### Seam 4 — the collapsed row label helper (new function, existing seam class)

Prior art: the swap label helper, which is called directly from the controller
suite with a JSON argument and asserted on its returned string. The encryption
label helper is tested identically — four render states plus the override dot,
with no fzf and no screen render involved.

### VM

The guided encrypted fixture exercises manifest → `zpool create` for real once
the harness preset is removed. An install producing an unlockable pool then
fails the smoke run rather than passing it. No new fixture is added; ADR 0048
notes a curated subset that actually runs beats a fuller one that does not.

## Out of Scope

- Changing the account password default. Root, per-user and the `--unattended`
  root default all keep `12345`.
- Extracting a pure passphrase resolver. The existing seam already proves the
  ladder; a new one would duplicate coverage.
- Reworking the age-decrypted secret path or SOPS activation.
- Per-group and data-pool encryption, which remain independent booleans on their
  own editors.
- Any change to the replay seam or the guided answers vocabulary.
- Adding a new VM fixture.
- Retroactively editing ADR 0054 or ADR 0055; both stay immutable and are
  superseded in the usual way.
- Re-introducing a Proceed gate on any secret.

## Further Notes

Two live bugs are fixed incidentally, and both are worth calling out in review
because neither is visible from the feature description:

1. The `12345` default is five characters and ZFS requires eight, so guided
   encrypted installs with no override have never been able to complete.
2. `install.sh --profile <encrypted> -y` hangs on a tty prompt inside a run that
   promised no prompts.

The second-order finding is that the harness preset shadowed the seam that hid
the first bug. A preset that bypasses the code path under test is not coverage,
and the removal is the most valuable single line in this change.

The accepted security posture is unchanged in kind from ADR 0055: a Proceed with
no overrides installs the disk passphrase as a known default, bounded by the
always-on `WILL ERASE` review and typed-`INSTALL` confirmation.
