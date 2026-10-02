# 22: borgmatic timer succeeds

**What to build:** Diagnose on a held VM why borgmatic.service fails when
forced; fix. Fixes F1000 (printed F000) and borgmatic journal Findings.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Root cause noted in Comments
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base
timers)

## Comments

Root cause: no config at /etc (it was under ~), stale schema, timer enabled
before any repo. Template now /etc/borgmatic/config.yaml.example (flat
schema); timer gated on the real config (c0d766a); timer probe reports SKIP
(8103590).
