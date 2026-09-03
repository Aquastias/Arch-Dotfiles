# 03 — Bounded redundancy pass

**What to build:** A smaller test suite that stays green, with no bug-class
losing its guard. Remove only **true duplicate-assertion pairs** (two tests
asserting the same behaviour/bug-class) and **fixtures fully superseded** by an
exhaustive/property successor (the regression catalog's "few-fixture →
exhaustive" cases). Consolidate rather than delete when unsure; keep every unique
bug-class the regression catalog guards. This is a bounded pass over the
catalogued supersessions and obvious duplicates — not a full 195-file audit.

**Blocked by:** 01 (a green baseline is required to verify "still green after
removing a test").

**Status:** ready-for-agent

- [ ] `run.sh --full` is still green after the pass; the file/test count is
      lower.
- [ ] Every removal is either a true duplicate of a surviving test or a fixture
      fully covered by a named exhaustive/property successor — each with a stated
      justification.
- [ ] No bug-class row in the regression catalog loses its guarding test; the
      catalog is updated where a guard's name changed.
- [ ] Where behaviour was worth keeping but duplicated, tests are consolidated
      rather than dropped, preserving the assertion.
- [ ] No full 195-file audit and no removal of a unique bug-class are in scope.
