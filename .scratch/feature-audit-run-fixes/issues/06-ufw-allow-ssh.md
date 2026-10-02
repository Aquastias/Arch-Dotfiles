# 06: ufw allows ssh when ssh is enabled

**What to build:** A host with ufw and ssh.enabled allows ssh, so the
operator (and the harness) can reach it. Fixes F387-F389, F405.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Arch Wiki-grounded
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (ufw):
sessions ready, probes staged
