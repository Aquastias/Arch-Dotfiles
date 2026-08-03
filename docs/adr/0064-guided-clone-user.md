# Guided Installer: clone a user from the User Editor

The User Editor (ADR 0051) gains a **`⧉ Clone this user`** row. Enter drops to a
name-entry text screen (a `__cloneuser__` variant of `__newuser__` carrying the
source name on the nav); a valid, non-duplicate name creates a **new ad-hoc
user** seeded with the source's **effective account-shape** — `shell`, `sudo`,
`groups`, `programs` — and lands in the clone's editor. Blank backs out to the
Users list; a duplicate (committed or already-listed) is refused with the same
notice the create path uses.

The clone is **always ad-hoc**: no `users/<name>/profile.jsonc` is written, so
the copied fields materialise as a full install-scoped delta in the userforms
file, exactly like a session-created user's. Cloning a committed user therefore
copies its *values*, not its committed status — the source file is untouched,
and the "Save never overwrites committed" invariant (ADR 0036 / 0051) holds.

The copy is **shape, not identity**. `git identity` and `SSH authorized keys`
are **not** carried across — they identify a specific human, and the point of a
clone is the same setup for a *different* who. The **password is never copied**
either; the clone lands password-less, so the Proceed gate (ADR 0049) stays
blocked until set — the same safety the create path relies on. The source is
read from the **effective** view (committed `⋆` this-session overrides), so an
operator clones what the editor is showing, including tweaks made this session.

The row renders in every context, including non-persistent ones with no
`GUIDED_USERFORMS_FILE` wired (preview / replay / test): there it still adds the
name but copies no delta — the same graceful degradation every other User Editor
edit already exhibits, keeping the render unconditional.

## Considered Options

### Trigger surface
- **Row inside the User Editor** — chosen. The source is unambiguous (the user
  being edited), one action, no source-picker step; reuses the editor that
  already owns per-user actions.
- **Action row on the Users list** — rejected. Discoverable next to
  `+ Create user`, but needs a two-step source pick then name.

### What the clone copies
- **Account-shape only (shell, sudo, groups, programs)** — chosen. Copies the
  *setup*, leaving identity and credentials to be set deliberately.
- **Everything incl. git identity + SSH keys** — rejected. Truest "clone" but
  silently grants the source person's keys and commit identity to a new account.

## Consequences

- Extends ADR 0051; the userforms delta shape, Proceed merge, and Save-warn
  (committed-user-only) predicate are unchanged — a cloned ad-hoc user never
  triggers the committed-edit warning.
- Covered by bats (`enter(text __cloneuser__)` copy / duplicate / blank, the
  editor row, and the clone nav) over the pure controller.

## Status

accepted — extends ADR 0051 (User Editor)
