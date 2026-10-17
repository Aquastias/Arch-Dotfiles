# 01: Package Resolver reports Host Programs and User Programs

**What to build:** `explain-packages` (and the Guided derived section, which
shares the Package Resolver) answers "what lands on this machine?" in full:
every Host Program and every User Program of each declared user is resolved to
the packages it installs and reported under its own source. Today both are
missing, so a Host Profile's real install set is invisible. See PRD
(`../PRD.md`) and [[ADR 0157]].

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Host Programs (authored, base, Menu-Owned) appear as a tagged source
- [ ] Each user's programs (User Core folded under the User Profile) appear as
      a tagged source naming the user
- [ ] `--sources` and `--flat` include them; `--flat` stays sorted/unique
- [ ] The Guided derived section agrees with `explain-packages` for the same
      Effective Config
- [ ] `explain-packages` bats cover both new sources; suite green
