# 05: Guided variant reaches the harness repo

**What to build:** The guided test flow serves/reaches the audit's dumb-HTTP
repo, so the guided install runs to completion and boots. Fixes F003.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (guided)

## Comments

flow-test serves its HTTP root when REPO_URL points there; guided gets the
audit CACHE_DIR (d947b7b).
