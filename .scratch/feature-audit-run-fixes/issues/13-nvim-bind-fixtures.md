# 13: nvim bind fixtures

**What to build:** nvim bind scenes set up what each bind needs (folds, http
request buffer, git remote, diff, tag stack), so a failure means a broken
bind. Fixes F570-F584 and similar.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base
probes-online)

## Comments

Root causes: key.lua ran before VimEnter (VeryLazy plugins absent) and IFS
tab-collapse shifted 'needs'. Plus folds/remote/REST loopback fixtures,
chord+action matching, silent! errmsg (1f3c1f0, 8dbafc1); refactoring.nvim
ported to its operator API (9890701).
