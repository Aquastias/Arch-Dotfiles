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

**Status:** done

- [x] No `@test` body in `.installer/tests/` has a non-final `! cmd` line
- [x] The lint rule flags a planted non-final `! cmd` and passes a final one
- [x] Any test that turns red is triaged: a real bug is fixed or filed, a
      stale assertion is corrected — never deleted to go green
- [x] Full suite green

## Comments

- 166 non-final `! cmd` lines became `! cmd || return 1` (safe as a loop's
  last line, unlike `cmd && return 1`). The lint rule `negated-assertion`
  (`readability-negation.awk`) allows a final `! cmd`, `! cmd || …`, and
  `readability-ok`.
- Two went red, both stale assertions (no product bug): the qt6ct check
  matched the file's own header comment; the impermanence tmpfiles check
  grepped `/etc/a.b` as a regex, so `.` hit the kept `/etc/aXb`.
- Full suite: 4148 tests, green after the two corrections.
