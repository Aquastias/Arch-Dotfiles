# 05: Pilot: install entry path

**What to build:** The install entry path — entry scripts, top-level
installer libs, the Installer Stdlib and the Shell Stdlib, with their
tests — follows ADR 0167: every command and flag it keeps has a Tool
Reference entry, banned bash and jq features are rewritten as plain bash
loops over simple jq output, inline awk moves to commented `.awk` files, long
pipelines and chains are split into named steps with a "what" comment, and
`parent_directory`/`base_name` calls become `dirname`/`basename`. Behavior
is unchanged. The area joins the Migrated Areas list, so the rules are
strict there from now on.

**Blocked by:** 02, 03

**Status:** ready-for-agent

- [ ] Area added to Migrated Areas; strict Readability Lint passes
- [ ] Tool Reference entries added for every command/flag the area keeps
- [ ] No `parent_directory`/`base_name` calls left in the area
- [ ] Frozen strings untouched (profile keys, CLI flags, env vars, target
      paths, grepped strings)
- [ ] Any `readability-ok: perf` line carries a measured before→after
- [ ] Area bats files pass (`-j 4` max); audit passes
- [ ] VM install passes; owner reviews the style before tickets 06–15 start
