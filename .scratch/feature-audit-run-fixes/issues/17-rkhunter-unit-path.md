# 17: rkhunter unit runs its real script

**What to build:** The rkhunter scan unit execs the script where the
installer installs it; the timer succeeds. Fixes F999 and rkhunter journal
Findings.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base
timers)

## Comments

Unit path fixed + exec-path test (a5d1601); the scan also needed the whole
Shell Stdlib staged (f8b5ffb).
