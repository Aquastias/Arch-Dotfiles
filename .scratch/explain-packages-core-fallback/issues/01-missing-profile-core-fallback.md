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

**Status:** done

- [x] Decide: core-only fallback for a missing profile, or abort (today)
- [x] If fallback: key it on the loader's actual missing-profile status
- [x] explain-packages.bats covers the chosen behaviour

## Comments

2026-10-11: chose the core-only fallback (the original intent). The loader
returns 1 with the core JSON for a missing profile (the earlier "returns 2"
probe ran without INSTALLER_DIR); explain_load_profile now captures the real
status. Covered by explain-packages.bats ("a missing profile …").
