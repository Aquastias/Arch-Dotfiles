# 01: Static audit misses the users/vm/ fallback

**What to build:** `tests/audit.sh` fails `host:arch-secure → user 'test' not
found in users/` and `host:arch-data → user 'data' not found in users/`.
Those users live under `users/vm/<name>/`, which the profile loader falls
back to (`_profile_load`) but the audit's user check does not. Same failure
at HEAD `d450d93` (found 2026-10-11 during readability ticket 11), so not a
refactor regression. Teach the audit the same `users/vm/` fallback.

**Blocked by:** None (can start immediately)

**Status:** needs-triage

- [ ] audit.sh resolves users via users/<name>/ then users/vm/<name>/
- [ ] audit.sh green on the current tree
