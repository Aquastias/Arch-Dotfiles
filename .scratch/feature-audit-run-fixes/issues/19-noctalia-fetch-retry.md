# 19: Noctalia plugin fetch retry

**What to build:** Plugin fetch retries shallowly with backoff before
skipping, so a network blip does not drop plugins.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (kernels,
greetd)
