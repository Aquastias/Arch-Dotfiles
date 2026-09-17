Status: done

# `programs_inherit: false` user bareness

## Parent

`.scratch/program-config-architecture/PRD.md` (ADR 0134).

## What to build

A user bareness flag mirroring the host's `packages.inherit`. A User Profile
with `programs_inherit: false` starts with no Core programs and takes only what
it names — scoped to `programs` only, so `groups`, `shell`, `sudo`, and
`ssh_authorized_keys` still inherit from User Core. `programs` stays a JSON
array; `programs_inherit` is a sibling boolean key (never a `{inherit, list}`
object reshape).

## Acceptance criteria

- [ ] Layer Resolver drops the lower layer's `.programs` before the fold when a
      user layer sets `programs_inherit: false`, mirroring the existing host
      `packages.inherit == false` handling; scoped to `.programs` only.
- [ ] `groups`/`shell`/`sudo`/`ssh_authorized_keys` still fold normally under
      `programs_inherit: false`.
- [ ] `programs_inherit` (bool, default true) accepted by the closed user
      schema; `programs` as an object is rejected; unknown keys still abort.
- [ ] Absent flag behaves exactly as today.
- [ ] Resolver unit tests (bats): bare-user yields no inherited programs while
      identity keys still inherit; absent flag unchanged; a user re-adding a
      program after a bare base still lands it. Prior art: the Layer Resolver
      classification/coverage test.

## Blocked by

- None — can start immediately.
