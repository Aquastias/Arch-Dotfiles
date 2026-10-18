# 01: Make negated bats assertions actually fail

**What to build:** every negative assertion in the installer suite can fail.
In bats, a `! cmd` line that is not a test's last line never fails the test
(bash `set -e` ignores a `!`-negated command), so many `! grep …` / `! echo … |
grep …` checks across `.installer/tests/` test nothing. Rewrite them to a form
that fails (`run …; [ "$status" -ne 0 ]`, or `cmd && return 1`), and add a
Readability Lint rule that rejects a non-final `! cmd` line in a `@test` body
(escape hatch: `readability-ok`). Found during the neutral-core work (ADR
0157), where the new tests already use the failing form.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] No `@test` body in `.installer/tests/` has a non-final `! cmd` line
- [ ] The lint rule flags a planted non-final `! cmd` and passes a final one
- [ ] Any test that turns red is triaged: a real bug is fixed or filed, a
      stale assertion is corrected — never deleted to go green
- [ ] Full suite green
