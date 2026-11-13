# 14: Feature Audit + matrix

**What to build:** The Feature Audit libs (its `.awk` files gain headers
and per-rule comments) and the combination matrix libs, with their tests,
follows ADR 0167: every command and flag it keeps has a Tool Reference
entry, banned bash and jq features are rewritten as plain bash loops
over simple jq output, inline awk moves to commented `.awk` files, long
pipelines and chains are split into named steps with a "what" comment, and
`parent_directory`/`base_name` calls become `dirname`/`basename`. Behavior
is unchanged. The area joins the Migrated Areas list, so the rules are
strict there from now on.

**Blocked by:** 05

**Status:** ready-for-agent

- [x] Area added to Migrated Areas; strict Readability Lint passes
- [x] Tool Reference entries added for every command/flag the area keeps
- [x] No `parent_directory`/`base_name` calls left in the area
- [x] Frozen strings untouched (profile keys, CLI flags, env vars, target
      paths, grepped strings)
- [x] Any `readability-ok: perf` line carries a measured before→after
- [x] Area bats files pass (`-j 4` max); audit passes
- [ ] A Feature Audit run in the VM passes
