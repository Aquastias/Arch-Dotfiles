# 15: nvim plugins installed at install

**What to build:** Install runs a headless lazy restore from the lockfile as
the user and stages it for /etc/skel and /root, so nvim (LSP, DAP, binds,
theme) works offline on first launch (ADR 0135). Fixes the nvim runtime-fetch
Findings.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base
probes-offline)

## Comments

lazy-lock.json committed; Lazy! restore at install for user and root from a
writable copy (58d860d, 6d33cac); orgmode grammar built at install (e9f29e3).
/etc/skel not staged: plugins would be copied per new user; deliberate.
