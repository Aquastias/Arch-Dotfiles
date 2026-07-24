# User Editor: full profile fields + create-into-editor with defaults

Status: done (afd97de)
Type: AFK

## Parent

`.scratch/guided-users-editor-inline-passwords/PRD.md` (ADR 0051).

## What to build

Extend the User Editor to the full User Profile: `sudo` (toggle), `groups`
(multi-select), `git name` / `git email` (text), `SSH authorized keys` (list add),
and `programs` (multi-select over resolvable program names). Each authors into the
same session per-user delta, install-scoped, with committed users displaying
effective values.

Upgrade `＋ Create user` to drop straight into the User Editor after the name is
typed, seeded with defaults **shell bash, sudo on, groups [wheel]** — so the
required password and other fields are set immediately. Reject a name that
collides with an existing committed or session user. Unify the two prior
disagreeing new-user sudo defaults (the replay create path's `sudo:false` and the
materialize fallback's `sudo:true`) onto **sudo on / wheel**, so both the
interactive and replay paths agree.

A created name left untouched still materializes the default profile
(bash + wheel) at Proceed.

## Acceptance criteria

- [ ] Editor exposes sudo, groups, git name/email, ssh keys, programs, each
      committing the expected per-user delta.
- [ ] `＋ Create user` → name prompt → lands in the editor with bash / sudo on /
      wheel defaults.
- [ ] A duplicate name (committed or session) is rejected with an actionable
      message; no partial user is created.
- [ ] The interactive create and the replay create path produce the same default
      profile (sudo on / wheel).
- [ ] A created-but-untouched user still materializes the default profile at
      Proceed.
- [ ] Controller/emit-seam bats cover each field's delta authoring, the create
      defaults, and the duplicate-name rejection.

## Blocked by

- `02-user-editor-shell-install-scoped.md`
