# User Editor screen: shell + enabled/remove, install-scoped

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/guided-users-editor-inline-passwords/PRD.md` (ADR 0051).

## What to build

Add a per-user **User Editor** screen, opened by Enter on a user row in the
flattened Users list. This slice ships the thinnest complete editor: the
`enabled` row (committed users) OR `✗ remove user` row (session-created users),
plus a `shell` row that cycles bash / zsh / fish. A committed user is never
removable; a session-created user has no `enabled` row.

Per-user edits are **install-scoped**. The editor authors a per-user delta (via
the existing `guided_user_profile` — prune empties, drop name) held in a session
per-user form map, extended to cover committed users as well as ad-hoc ones. A
committed user's editor displays its **effective** (core-merged) values but stores
only the delta. At Proceed the delta is materialized onto the **install clone's**
user profile; the committed repo file is never written. Export bakes it in the
same way.

`enabled` toggling a committed user adds/removes its name in `.users`; disabling
the last user is permitted (a root-only install), with the existing
`post_install_guard_users` remaining the only block (Security/Backup Extras
selected but no primary user). `.users` stays names-only — no profile data enters
the Config State.

## Acceptance criteria

- [ ] Enter on a user opens the User Editor; Esc returns to the flattened list.
- [ ] Committed user shows `enabled` (toggle) + `shell` (cycle); ad-hoc user shows
      `✗ remove user` + `shell`, no `enabled`.
- [ ] Cycling shell commits a per-user delta; a committed user renders effective
      values (e.g. groups from its profile) while storing only the delta.
- [ ] Proceed materializes the delta onto the install clone; the committed repo
      `users/<name>/profile.jsonc` is byte-identical afterward.
- [ ] Disabling the last user yields a userless (root-only) config that Proceeds
      when no extras are selected and blocks (existing message) when they are.
- [ ] `.users` remains names-only in the Config State after any editor edit.
- [ ] Editor edits are captured by the undo/redo autocommit like any other edit.
- [ ] Controller/emit-seam bats cover delta authoring, effective-view display, and
      the enabled/remove dispatch.

## Blocked by

- `01-flatten-users-toplevel-warn.md`
