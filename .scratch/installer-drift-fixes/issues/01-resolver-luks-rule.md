# 01: Package Resolver reports LUKS userland on the global flag, not per group

**What to build:** `_package_resolver_filesystem_sets`
(`lib/packages/package-resolver.sh`) emits the `luks` set when
`.options.encryption` is true and any group is non-zfs. The install list
uses `install_config_any_nonzfs_luks` (ADR 0043): root OR any data pool that
is a non-zfs ENCRYPTED group. They disagree:

- zfs root + encrypted ext4 data pool: install adds cryptsetup;
  `explain-packages` / the Guided derived section omit it.
- encrypted zfs root + plaintext ext4 data pool: resolver reports
  cryptsetup; install does not add it.

Apply the per-group rule in the resolver (jq over the Effective Config,
it holds JSON not CONFIG_FILE). A parity test pins resolver = install
predicate on shared fixtures until the Install Config Reader accepts JSON
(architecture review candidate #1).

**Blocked by:** None (can start immediately)

**Status:** done

- [x] Resolver emits `luks` iff `install_config_any_nonzfs_luks` is true
- [x] bats: both mismatch cases above
- [x] bats: parity over shared fixtures

## Comments

2026-10-13: Resolver emits `luks` on the per-group rule (jq restatement in
`_package_resolver_filesystem_sets`). tests/packages/resolver-derived-sets.bats:
both mismatch cases + 9-fixture parity vs `install_config_any_nonzfs_luks`
(red → green); packages + luks bats green; readability.sh clean.
