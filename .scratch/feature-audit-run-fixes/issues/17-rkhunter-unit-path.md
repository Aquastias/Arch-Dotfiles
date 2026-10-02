# 17: rkhunter unit runs its real script

**What to build:** The rkhunter scan unit execs the script where the
installer installs it; the timer succeeds. Fixes F999 and rkhunter journal
Findings.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base
timers)
