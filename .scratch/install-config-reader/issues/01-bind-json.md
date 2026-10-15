# 01: Bind JSON in the Install Config Reader; resolver and gate use it

**What to build:** the Install Config Reader can be bound to an Effective
Config held as JSON (in memory), not only the `CONFIG_FILE` file. Every
generated accessor and hand-written derived predicate (any-ZFS, any-LUKS, …)
reads the bound config; file callers are unchanged. Binding is global state,
so JSON callers bind inside a subshell. The Package Resolver's LUKS rule and
the Feature Audit Probe Gate's any-ZFS rule call the reader instead of their
jq restatements (installer-drift-fixes 01/03); the restatements and their
parity tests are deleted. Decisions: architecture review candidate #1, Q15
(bind) — extends ADR 0015.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] Accessors + derived predicates read a bound JSON config
- [x] File-based callers behave identically (existing suite green)
- [x] Resolver LUKS set and gate any-ZFS go through the reader
- [x] Both jq restatements + parity tests deleted; behaviour tests kept
- [x] Binding cannot leak between callers (subshell-scoped; test proves it)

## Comments

2026-10-15: Prefactor 3e19930 split the per-group accessors into
install-config-groups.sh (install-config.sh was at the 500-line cap).
`install_config_use_json <json>`; every reader read goes through
`_install_config_read` (bound JSON, else CONFIG_FILE). Resolver LUKS set and
gate any-ZFS bind inside `$(…)`; jq restatements + parity tests deleted,
behaviour tests kept (+ gate: zfs storage group keeps snapshots).
tests/config/install-config-bind.bats (6). Full suite 3615/3615.
