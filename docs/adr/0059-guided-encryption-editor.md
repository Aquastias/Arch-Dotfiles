# Guided Encryption Editor + 8-char default disk passphrase

---
Status: accepted
---

The Guided Installer's two encryption surfaces — the `encryption` toggle and the
`encryption password` row on **Disks**, plus the `disk encryption` row on
**Users** — collapse into a single **Encryption Editor** drilled from one
`Encryption ▸` row. The default disk passphrase becomes **`12345678`**, not the
`12345` every other secret uses, and that default now also reaches the back end
under `--unattended`.

The 8th character is not cosmetic. ZFS `keyformat=passphrase` rejects anything
shorter at pool creation, so the `12345` default ADR 0055 gave the passphrase
**could never install**.

This supersedes ADR 0054 on the passphrase row's **location only** — its ≥8-char
entry rule and its toggle-off-retain lifecycle survive unchanged — and ADR 0055
on the **single override surface** and the **`12345` disk default**.

## The bug ADR 0055 introduced

ADR 0054 enforced ZFS's ≥8 minimum in the menu, deliberately: *"a 1–7 char
passphrase would pass the menu and blow up at `zpool create`."* ADR 0055 then
made every unset secret default to `12345` — five characters — without
reconciling the two. The menu still refused a short **typed** passphrase while
the **default** was short by construction.

So any guided encrypted install that did not override the passphrase died at
`zpool create`. Both shipped personal profiles (`desktop`, `laptop`) are
encrypted, which is to say the one-select install ADR 0055 existed to deliver
was the exact path that failed.

Accounts keep `12345`. Nothing enforces a floor on them, and a single shared
default would have churned `chroot.sh`, `profiles/runner.sh` and the
`--unattended` root default for no gain. The asymmetry is the point: the disk
passphrase is longer **because ZFS says so**, and that reason lives in one
comment beside one constant, `INSTALL_DEFAULT_ENC_PASSPHRASE`, shared by the
manifest builder, the display tag and the pool creator.

## Why the tests missed it

`_seed_generator_render_guided_user_data` exported
`INSTALL_ENC_PASSPHRASE='testtest'` for every encrypted **guided** VM run. That
is precedence **tier 1**, so it shadowed the guided manifest entirely: no VM had
ever run the path the menu actually produces. The preset was copied from the
non-guided flow, where it is genuinely required — there is no manifest to read.

The preset is removed from the guided path only. `guided-secure` — the sole
fixture that is both guided and encrypted, and install-only — now exercises
manifest → `zpool create` for real, at no new VM cost. Non-guided fixtures keep
`testtest`.

This is the ADR 0048 create-time class, the one that tier claims is *"already
exercised on every VM install."* It was not, because the seam under test was
shadowed by the harness. A preset that bypasses the code path is not coverage.

## `--unattended` reaches the back end

`collect_enc_passphrase` gains a third tier:

1. `INSTALL_ENC_PASSPHRASE` — test/VM preset
2. guided manifest
3. **`INSTALL_UNATTENDED=1` → `12345678`** — new
4. interactive tty prompt

`install.sh --profile desktop -y` promises to *"bypass every interactive
confirmation"* and then blocked on a tty passphrase prompt, because `desktop` is
encrypted and nothing non-guided supplied a passphrase. Tier 3 closes that. It
is deliberately **not** unconditional: an interactive profile install still
prompts, because silently encrypting a machine with a known default the operator
was never shown or asked about is worse than asking. `chroot.sh` already gates
root's `12345` default on the same variable.

## The Encryption Editor

One `Encryption ▸` row on Disks, kept in its existing slot beneath `filesystem`
— the filesystem is what derives the cipher (ADR 0040). It collapses the state
that matters:

```
Encryption ▸ on · default 12345678
Encryption ▸ on · custom              ●
Encryption ▸ on · from age
Encryption ▸ off
```

Spelling the literal default on the row preserves ADR 0055's deliberate choice
to make a weak default visible **without drilling**. Burying it one level down
would have regressed the only thing making that posture defensible.

Enter opens the Editor, which expands and collapses exactly as `swapedit`
already does for swap:

```
enabled: false          enabled: true
← Back                  password: default 12345678
                        ← Back
```

`enabled` cycles in place rather than drilling to a `true`/`false` list — three
levels for a boolean, which is what nesting the existing `enum` machinery would
have produced. The passphrase row is **hidden while encryption is off**: it
configures nothing in that state. The stored value is retained regardless (ADR
0054), so a fat-finger toggle still costs nothing.

Setting a passphrase does **not** enable encryption. The toggle stays the single
source of truth for whether the disk is encrypted; a side effect that quietly
flips it would mean an operator could arrive at an encrypted install without
ever having chosen one.

The `disk encryption` row leaves the Users screen. One secret, one door. ADR
0055's "single override surface" narrows to **accounts**, and the disk
passphrase sits beside the toggle that gives it meaning.

## TUI glyph vocabulary

ADR 0055's prose says the age-decrypted tag renders `🔒 from age`. It never did
— the emoji appears nowhere but that one line of that one document, and is not
adopted here.

Rendered TUI output stays limited to narrow geometric unicode (`⚠ ● ▸ ✓ ← ·`).
Emoji are double-width and width-ambiguous across terminals, which breaks
alignment in the persistent fzf (ADR 0042). The convention was already implicit
in every screen; recording it here stops the next reader from "fixing" the code
to match 0055.

## Considered Options

### Merge scope
- **All three surfaces** — chosen. Removes the duplicate door and the
  0054-vs-0055 render split (`(not set) ⚠` on Disks, `default 12345` on Users)
  in one move.
- **Only the two Disks rows** — rejected. Leaves two live editors writing the
  same manifest key.
- **Only the two password rows** — rejected. Dedupes the secret but leaves the
  toggle stranded from the thing it toggles.

### Passphrase row while encryption is off
- **Hidden, value retained** — chosen, matching `swapedit`'s existing collapse.
  A field that configures nothing should not be on screen.
- **Always visible but inert** — rejected. Invites the operator to set something
  that does nothing.

### Setting a passphrase auto-enables encryption
- **No** — chosen. Enablement stays an explicit choice.
- **Yes** — rejected. Two routes to an encrypted install, one of them implicit.

### Default value scope
- **`12345678` for the disk only** — chosen. Only the passphrase has a floor.
- **`12345678` everywhere** — rejected. Churns four unrelated call sites and the
  `--unattended` root default to fix a ZFS-specific constraint.

### Back-end default
- **`--unattended` only** — chosen. Unblocks `--profile <encrypted> -y` while
  keeping the interactive prompt honest.
- **Unconditional** — rejected. Encrypts an interactive operator's disk with a
  default they were never shown.
- **Guided only** — rejected. Leaves `--profile desktop -y` hanging.

## Consequences

- A Proceed with no override installs the disk passphrase as `12345678`. This
  extends ADR 0055's recorded posture rather than changing it, and leans on the
  same guard: the always-on `WILL ERASE` review and typed-`INSTALL` gate.
- `_ctl_secret_tag` returns a role-dependent default string, so the Users screen
  and the Encryption Editor disagree on the digits by design.
- `options.encryption` stays in `_MENU_FIELDS` — it still drives the override
  dot and the Disks category summary — but its row render is special-cased, the
  same way the passphrase row already was.
- The replay seam (`_guided_edit_encryption`, `encryption=true`) is untouched,
  so the VM harness drives the menu exactly as before.
- **VM-verifiable.** Dropping the harness preset means the guided manifest
  passphrase reaches a real `zpool create`; an install that produces an
  unlockable pool now fails the smoke run rather than passing it.
