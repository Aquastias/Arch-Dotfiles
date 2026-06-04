# Multi-principal / `@group` ACL ownership

Status: done

## Parent

`.scratch/pool-owners-access/PRD.md`

## What to build

Extend `owners` to a list mixing users and `@groups`. When the list has
more than one principal or any `@group`, the mountpoint is shared via
POSIX ACLs: the first listed user is the nominal owner, every listed
user and `@group` gets an `rwx` grant, and matching default-ACLs are set
so newly created files inherit access (the ACL mask is set to allow
`rwx`). Group grants reference the User Config `groups` system, so
membership stays dynamic. Every user with access — listed users plus
members of listed groups — receives a `~/Disks/<pool>` symlink.
Validation rejects a `@group` with no declared members.

## Acceptance criteria

- [ ] A pool with `owners: ["alice", "@family"]` is writable by alice
      and by every member of `family`, including files created by other
      members (default-ACL inheritance).
- [ ] Adding a user to a named group grants access without re-running
      the installer.
- [ ] Every user with access gets a `~/Disks/<pool>` symlink.
- [ ] A `@group` with no declared members fails validation.
- [ ] The Owners Resolver's ACL plan (entries, base owner, access-user
      set) is unit-tested across single-user, multi-user, single-group,
      and mixed cases.

## Blocked by

- `issues/03-owners-single-user-override.md`
