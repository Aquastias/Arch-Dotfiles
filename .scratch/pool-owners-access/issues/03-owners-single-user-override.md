# `owners` single-user override (schema + validation)

Status: ready-for-agent

## Parent

`.scratch/pool-owners-access/PRD.md`

## What to build

Add the optional `owners` field to each `data_pools[]` and
`storage_groups[]` entry in the Install Config, with config accessors.
When `owners` names a single user, that user — not necessarily the
Primary User — owns the mountpoint and receives the `~/Disks/<pool>`
symlink. The Owners Resolver reads the field; the Layout Module's
validation rejects an `owners` entry naming a user that is not declared,
so a typo aborts the install before any disk work rather than silently
leaving a pool inaccessible.

## Acceptance criteria

- [ ] A data pool / storage group with `owners: ["<user>"]` is owned by
      that user after install (`chown`, no ACL).
- [ ] Omitting `owners` still defaults to the Primary User (slice 02
      behavior unchanged).
- [ ] An `owners` entry naming an undeclared user fails validation with
      a clear message before any disk is touched.
- [ ] The Owners Resolver's single-user path and the validation are
      unit-tested.

## Blocked by

- `issues/02-default-ownership-primary-user-symlinks.md`
