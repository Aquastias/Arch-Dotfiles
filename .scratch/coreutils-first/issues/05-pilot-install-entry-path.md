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

**Status:** done

- [x] Area added to Migrated Areas; strict Readability Lint passes
- [x] Tool Reference entries added for every command/flag the area keeps
- [x] No `parent_directory`/`base_name` calls left in the area
- [x] Frozen strings untouched (profile keys, CLI flags, env vars, target
      paths, grepped strings)
- [x] Any `readability-ok: perf` line carries a measured before→after
- [x] Area bats files pass (`-j 4` max); audit passes
- [x] VM install passes; owner reviews the style before tickets 06–15 start

## Comments

- Code done; full suite 4103/4103 green. Open: VM install (host had
  ~11 GiB free, below VM RAM + 8 GiB) and owner style review.
- 2026-11-12: owner approved the style; VM install of
  `desktop/combined-sops-impermanence` (76fdc31) passed: system running, no
  failed units, pools ONLINE, /persist mounted, sops-runtime active.
