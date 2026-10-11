# 01: explain-packages never falls back to core-only

**What to build:** `tools/explain-packages.sh` meant to report Host Core
alone ("no profile '<name>' — resolved core only.") when the profile loader
returns 1, and abort on any other failure. The branch never ran: it read
`rc=$?` inside `if ! effective="$(…)"`, where `$?` is the negation's 0, so
every load failure exited 1 with "could not load profile". The dead branch
was dropped in readability ticket 20 (behaviour unchanged). Decide whether
the core-only fallback is still wanted; if so, capture the loader's real
status and restore it (today `profile_loader_load nope` returns 2, not 1).

**Blocked by:** None (can start immediately)

**Status:** needs-triage

- [ ] Decide: core-only fallback for a missing profile, or abort (today)
- [ ] If fallback: key it on the loader's actual missing-profile status
- [ ] explain-packages.bats covers the chosen behaviour
