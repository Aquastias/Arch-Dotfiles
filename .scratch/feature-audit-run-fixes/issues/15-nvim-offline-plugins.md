# 15: nvim plugins installed at install

**What to build:** Install runs a headless lazy restore from the lockfile as
the user and stages it for /etc/skel and /root, so nvim (LSP, DAP, binds,
theme) works offline on first launch (ADR 0135). Fixes the nvim runtime-fetch
Findings.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base
probes-offline)
