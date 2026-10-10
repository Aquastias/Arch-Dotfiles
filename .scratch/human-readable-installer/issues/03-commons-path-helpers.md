# 03: Commons path helpers

**What to build:** Named helpers for a path's parent directory and base
name exist in each world — Installer Stdlib, the chroot common library,
Shell Stdlib — so area tickets can replace raw `basename`/`dirname`
with readable words. Never shared across worlds (Shell Commons).

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Helpers in all three worlds, named per the Readability Rules
- [ ] Unit tests in each world's existing stdlib bats file
- [ ] No call sites migrated yet (area tickets do that)
