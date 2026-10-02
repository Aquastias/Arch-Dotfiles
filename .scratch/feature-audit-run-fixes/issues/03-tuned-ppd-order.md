# 03: tuned without the ppd conflict

**What to build:** With power profile tuned, tuned + tuned-ppd land before
the DE packages so tuned-ppd provides power-profiles-daemon; no conflict
prompt aborts the install (ADR 0080). Arch Wiki-grounded. Fixes F002 (tuned).

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Arch Wiki page cited
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (tuned)
