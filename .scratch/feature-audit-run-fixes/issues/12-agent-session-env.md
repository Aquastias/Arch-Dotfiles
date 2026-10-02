# 12: Agent-launched apps get the session env

**What to build:** VM Agent Control launches apps with the user manager's
environment, so Qt sees the real locale (no 'locale C' warnings) and apps
behave as in a real session.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base
sessions)
