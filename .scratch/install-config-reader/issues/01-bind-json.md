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

**Status:** ready-for-agent

- [ ] Accessors + derived predicates read a bound JSON config
- [ ] File-based callers behave identically (existing suite green)
- [ ] Resolver LUKS set and gate any-ZFS go through the reader
- [ ] Both jq restatements + parity tests deleted; behaviour tests kept
- [ ] Binding cannot leak between callers (subshell-scoped; test proves it)

## Comments
