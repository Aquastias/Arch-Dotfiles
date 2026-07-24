# Save warns on install-only committed-user edits

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/guided-users-editor-inline-passwords/PRD.md` (ADR 0051).

## What to build

Close the silent-drop gap: when the operator has edited a **committed** user's
profile field in the User Editor and then picks **Save profile**, the edit is
install-scoped and will not be written to the saved profile (`.users` is
names-only; committed files are never rewritten). Make that explicit.

Add a pure predicate that, given the session per-user forms and the set of
committed users, returns the committed users carrying a non-empty delta. The Save
path calls it and, when non-empty, emits a warning naming those users and stating
the edits are install-only (edit the committed `users/<name>/profile.jsonc` to
persist). Save still writes the device-less Host Profile as usual and never
rewrites any committed user profile.

## Acceptance criteria

- [ ] The predicate returns exactly the committed users with a non-empty delta;
      empty when none (ad-hoc users are not reported by it).
- [ ] Save with a pending committed-user edit prints a warning naming the user(s)
      and the install-only caveat, then still writes the host profile.
- [ ] Save never modifies any `users/<name>/profile.jsonc`.
- [ ] Save with no committed-user edits produces no such warning.
- [ ] Bats cover the predicate (prior art: guided-save.bats).

## Blocked by

- `02-user-editor-shell-install-scoped.md`
