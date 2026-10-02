# 21: searxng running

**What to build:** Diagnose on a held VM why the searxng user unit is
inactive; fix so it answers on 127.0.0.1:8080. Fixes F585-F586.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Root cause noted in Comments
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base)

## Comments

Root cause: quadlets lived only in the repo-root stow tree; moved into the
program home so Config Apply ships them (6f179c3).
