# 01: Tool Reference + command/flag rules (expand)

**What to build:** The Tool Reference exists as a human doc under `docs/`
and the Readability Lint uses it as the allowlist. Each tool has a fixed
heading, a one-line meaning, its used flags as a fixed list (flag + one-
line meaning) and one real repo example — readable prose the lint can
parse. Seeded sections: Coreutils, Builtins, grep (`-q -E -F -v -x -c -o
-l`), sed (`-i` substitution), jq (flags `-r -e -c -n --arg --argjson`),
Domain Tools, bats. New rules `tool-reference` (command at command
position with no entry) and `flag-reference` (flag of an allowed command
with no entry) scan all tracked shell code (minus vendored skills,
`.scratch/`, program payloads). A **Migrated Areas** list makes the new
rules strict inside listed areas and advisory (shown by `--list`, never
failing) elsewhere, so the repo stays green during migration.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] Tool Reference doc with the seeded sections, each entry with meaning,
      flags and a real example
- [x] `tool-reference` and `flag-reference` rules report `rule: file:line:
      detail`
- [x] File set widened to all tracked shell code, exclusions honored
- [x] Migrated Areas list: strict inside, advisory outside; starts empty
- [x] Fixtures: unknown command, unknown flag, entry added flips result,
      strings/comments/heredocs ignored, exclusions, advisory vs strict
- [x] "this repo passes the strict Readability Lint" still green
- [x] Lint code added here follows ADR 0167 itself
