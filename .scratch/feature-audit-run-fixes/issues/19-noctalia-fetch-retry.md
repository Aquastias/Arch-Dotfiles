# 19: Noctalia plugin fetch retry

**What to build:** Plugin fetch retries shallowly with backoff before
skipping, so a network blip does not drop plugins.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (kernels,
greetd)

## Comments

Plugin fetch retried 3x with backoff (90e5e43).
