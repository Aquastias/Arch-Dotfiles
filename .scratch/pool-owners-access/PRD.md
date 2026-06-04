# Pool owners: user/group access for data pools

Status: done

See ADR 0031 (Pool `owners` access list via POSIX ACLs), ADR 0027
(Standalone Data Pools), ADR 0028 (stable device paths). Glossary:
Pool Owners, Primary User, Combined Data Pool, Standalone Data Pool,
Storage Group, Chroot Configuration Module, Runner.

## Problem Statement

After installing on a multi-disk machine, a person can't actually use
their data pools. The Combined Data Pool and Standalone Data Pool
mountpoints (under `/data`) are created `root`-owned, so a normal user
gets "permission denied" when writing to them. The desktop makes it
worse: the file manager lists the raw ZFS partitions as removable
drives, prompts for a password, then fails with "zfs_member not
configured in kernel" — and hiding those entries leaves no obvious way
to reach the data at all. On multi-user machines there is no way to say
"this pool belongs to these users" or "this pool is shared by this
group."

## Solution

Data pools become usable out of the box. Each pool declares an optional
**`owners`** access list whose entries are usernames or `@groups`. The
installer applies it: a single user gets plain ownership; multiple users
or any group are granted access via POSIX ACLs (with default ACLs so
newly created files inherit the grants). Everyone with access gets a
`~/Disks/<pool>` symlink that works in any file manager — GUI or TUI —
without per-app bookmarks. A udev rule stops the desktop from offering
ZFS members as broken removable drives. Omitting `owners` defaults to
the Primary User; on a host that declares no users, the pool is left
`root`-owned with a warning rather than failing the install.

## User Stories

1. As a person who just installed, I want my data pools writable
   without `sudo`, so that I can save files to them immediately.
2. As the Primary User, I want a pool with no declared owner to default
   to me, so that the common single-human case just works.
3. As an operator, I want to name a single owner per pool, so that the
   right user owns the right disk even when they aren't the first-listed
   user.
4. As a multi-user household, I want to grant a pool to a group, so that
   everyone in the family can read and write the shared media pool.
5. As an operator, I want to list several users and groups as owners of
   one pool, so that I can mix individuals and teams on the same
   storage.
6. As a member of a shared pool, I want files created by others to be
   writable by me, so that we collaborate without permission errors.
7. As an operator, I want adding a user to a group to grant pool access
   without re-running the installer, so that group membership stays the
   single source of truth.
8. As a person, I want each pool I can access to appear as
   `~/Disks/<pool>` in my home, so that I can reach it from any file
   manager.
9. As a ranger/yazi/Thunar user, I want pool access that doesn't depend
   on KDE bookmarks, so that it works in my file manager too.
10. As a KDE user, I want the file manager to stop offering ZFS members
    as removable drives, so that I don't get password prompts that fail
    to mount.
11. As an operator, I want an `owners` entry naming a non-existent user
    rejected, so that a typo fails the install instead of silently
    leaving a pool inaccessible.
12. As an operator, I want a group with no members rejected as an owner,
    so that I don't end up with a pool only `root` can use.
13. As an operator of a host with no declared users, I want pools left
    `root`-owned with a warning, so that the install doesn't fail just
    because there is no human to own them.
14. As an operator, I want both Storage Groups (Combined Data Pool) and
    Standalone Data Pools to support `owners`, so that ownership is
    consistent regardless of pool type.
15. As an operator using the interactive leftover-disk flow, I want the
    synthesized pool to default to the Primary User, so that I'm not
    forced into an `owners` prompt mid-install.
16. As an operator who backs up pools, I want to know shared pools use
    ACLs, so that I use ACL-aware backup flags.
17. As an operator, I want ownership applied at install time, so that a
    pool that briefly fails to import on first boot still has the right
    ownership baked into the dataset.
18. As a maintainer, I want the chown-vs-ACL decision isolated in one
    pure module, so that I can test it thoroughly without touching
    disks.

## Implementation Decisions

- **Owners Resolver (deep, pure).** Inputs: a pool's `owners` list, the
  set of declared users, and a group→members map. Output: an ownership
  plan — base owner, the ACL entries to apply, the set of users with
  access (for symlinks), and any validation errors. It owns the whole
  decision and never touches the filesystem.
- **Resolution rules.** Omitted `owners` → the Primary User. A single
  bare user → plain ownership (`chown`, mode `0755`), no ACL. More than
  one principal, or any `@group` → POSIX ACLs: the first listed user is
  the nominal owner; each listed user gets an `rwx` entry and each
  `@group` a group `rwx` entry, each mirrored as a default-ACL so new
  files inherit it; the ACL mask is set to `rwx`. `acltype=posixacl` is
  already set at pool creation.
- **`owners` element syntax.** A bare token is a username; an
  `@`-prefixed token is a group. Groups come from User Config's `groups`
  declarations; ACLs reference the group, so membership stays dynamic
  (not snapshotted).
- **Schema.** Add an optional `owners` array to each `data_pools[]` and
  `storage_groups[]` entry in the Install Config, with config accessors
  alongside the existing per-entry accessors.
- **Validation** lives in the Layout Module's `layout_validate`,
  delegating to the Resolver's pure validation: a bare name must be a
  declared user; an `@group` must have ≥1 declared member; either
  failure aborts the install. A host with no declared users leaves an
  *omitted*-`owners` pool `root`-owned with a warning (not an error);
  an *explicit* `owners` on such a host is still validated.
- **Owners Applier (thin I/O).** Consumes the plan: runs the
  ownership/ACL changes and creates the `~/Disks/<pool>` symlink in each
  access-user's home. Runs as a new install step inside the chroot after
  the Runner has created users and groups and while the pools are
  mounted under the altroot — so it is robust to a first-boot import
  hiccup.
- **udisks rule writer.** Emits a udev rule marking `zfs_member`
  partitions as ignored by udisks, written unconditionally by the Chroot
  Configuration Module (a harmless no-op when udisks2 isn't installed).
- **Interactive leftover→own-pool path** defaults `owners` to the
  Primary User silently — `owners` is a declarative-config feature.

## Testing Decisions

- A good test asserts the **external behavior** of the Owners Resolver:
  given an `owners` list plus the declared users and group map, assert
  the resulting plan (chown vs ACL, the entry set, the access-user set,
  the base owner, and validation errors) — never how it is computed.
- **Unit-test (bats) the Owners Resolver** across: omitted → Primary
  User; single user → chown plan; user + `@group` → ACL plan; multiple
  groups + users; undeclared user → error; empty group → error; the
  access-user set is the union of listed users and group members; base
  owner is the first listed user.
- **Prior art:** `zfs-pools.bats` (pure resolvers + validation reasons),
  `layout-multi.bats` (validation), `vm-pool-verify.bats` (stubbed
  system queries).
- **Integration:** extend the multi-data-pools VM smoke test to assert a
  data pool is owned by, and writable by, its declared owner on the
  booted system. The udisks rule and ACL application are otherwise
  covered by the Resolver unit tests plus manual confirmation.

## Out of Scope

- Per-user *differing* permissions on one pool (e.g. one user
  read-write, another read-only). `owners` grants uniform `rwx`;
  finer-grained ACLs are a later escalation.
- Interactive prompting for `owners` (declarative config only).
- Re-applying `owners` changes on an already-installed system (this is
  install-time only; a runtime ownership tool is future work).
- Per-pool encryption keys / per-user keys.

## Further Notes

- Operator caveats for ACL pools: `ls -l` shows a trailing `+`, and
  backup/sync tools must be ACL-aware to preserve grants (`rsync -A`,
  `tar --acls`; ZFS `send`/`recv` preserves them natively).
- The `~/Disks/<pool>` symlinks live in `/home`, so they persist across
  reboots and under impermanence.
