# 03: Raw config read lint with a ratcheting baseline

**What to build:** a lint (beside the Readability Lint, same ratchet idiom)
that fails on a raw jq read of an Install Config path with an inline
`// <default>` outside the Install Config Reader. Today's reads are recorded
in a baseline that may only shrink: a new raw read fails; removing one
without updating the baseline fails too. Decisions: candidate #1, Q18.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] New raw read outside the reader fails the lint
- [ ] Baseline lists today's reads; stale entries fail
- [ ] Wired into the always-on test run
- [ ] Agent doc says: read through the reader (bind for JSON)

## Comments
