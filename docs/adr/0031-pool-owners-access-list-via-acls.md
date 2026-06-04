# ADR 0031: Pool `owners` access list via POSIX ACLs

## Status
Accepted

## Context
Combined and Standalone Data Pools mount `root`-owned, so a human can't
write to them out of the box — the opposite of "clear access, no
problems." The default owner is the Primary User (ADR's glossary term:
the host's `users[0]`), but that is not enough on its own:

- The owner of a given pool is not always the first-listed user.
- Multi-user machines want to grant a pool to a *set* of principals —
  several users and/or named groups (e.g. a shared family pool).

A Unix directory has exactly **one** user-owner and **one** group-owner,
so an arbitrary mix of users and groups (`[aquastias, @family, @test,
marinela]`) cannot be expressed with `chown` + setgid. The only POSIX
mechanism that grants access to an arbitrary set of users *and* groups
is **access control lists**, which ZFS already supports here
(`acltype=posixacl` is set at pool creation).

## Decision
Add an optional **`owners`** field to each `data_pools[]` and
`storage_groups[]` entry: a list whose elements are either a **username**
or a **`@group`** name (the `@` sigil disambiguates the two namespaces).

Resolution at install time:

- **Omitted** → the Primary User. **Single bare user** → plain
  `chown <user>:` (no ACL) — the common case stays simple.
- **>1 principal, or any `@group`** → POSIX ACLs:
  - Base user-owner = the first listed user (so `ls -l` shows a human).
  - Each listed user → `u:<user>:rwx`; each `@group` → `g:<group>:rwx`,
    mirrored as **default** ACL entries so newly created files inherit
    the grants (the ACL equivalent of setgid). `setfacl` sets the ACL
    mask to `rwx` so the named grants are effective.
- `@group` reuses the existing per-user `groups` declarations in User
  Config; the ACL references the group, so membership stays **dynamic**
  — adding a user to `@family` later grants access without re-running
  anything.
- Every user with access (listed users ∪ members of listed groups) gets
  a `~/Disks/<pool>` symlink (ADR 0028 glossary / Primary User entry).

Validation (fail the install rather than half-break access): a bare name
must be a declared user; a `@name` must be a group with ≥1 declared
member.

The chown/ACL/symlink step runs install-time **after `run_profiles`**
(users and groups exist, pools are mounted under the altroot), so it
can't be defeated by a first-boot import hiccup. It runs on the host
against the altroot-mounted paths (`${MOUNT_ROOT}/data/...`,
`${MOUNT_ROOT}/home/...`), **resolving each owner to a numeric UID/GID
read from the installed system's `/etc/passwd` + `/etc/group`** — the
live ISO has no knowledge of the chroot's users, so a name-based `chown`
on the host would fail. ACL group grants are written as `g:<gid>:rwx`,
which still references the group, so membership stays dynamic.

## Considered alternatives
- **`chown` + one shared group + setgid.** Handles a single group only;
  cannot mix several groups plus extra users. Too narrow.
- **Flatten the list into one installer-created per-pool group.** Snapshots
  membership at install, so adding someone to `@family` afterwards would
  silently *not* grant access — it betrays the whole point of naming a
  group. Rejected.
- **A single `owner` (one user).** Doesn't express sharing. Kept only as
  the fast path when `owners` is one user.

## Consequences
- Multi-principal pools carry ACLs: `ls -l` shows a `+`, and backup/sync
  tools must be ACL-aware to preserve grants (`rsync -A`, `tar --acls`;
  ZFS `send`/`recv` preserves them natively). Documented for operators.
- Single-owner and default pools stay plain `chown` — no ACL surface in
  the common case.
- Group membership is sourced from User Config, so pool sharing and user
  group declarations are one source of truth.
- Builds on the Primary User default and ADR 0027 (data pools); the
  install-time placement matches ADR 0028's reasoning about not
  depending on boot-time pool state.
