# 06: ufw allows ssh when ssh is enabled

**What to build:** A host with ufw and ssh.enabled allows ssh, so the
operator (and the harness) can reach it. Fixes F387-F389, F405.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Arch Wiki-grounded
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (ufw):
sessions ready, probes staged

## Comments

ufw already allowed ssh (limit); its rate limit rejected the harness's
per-command SSH. Fixed by SSH multiplexing in vm-agent (aa0d235). ufw rule
files made root-only (fdadc63).
