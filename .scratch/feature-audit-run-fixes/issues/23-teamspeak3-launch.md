# 23: teamspeak3 launches or is unverifiable

**What to build:** Try env fixes (Qt platform, xcb) so the client launches
and stays up. If the abort is upstream, mark its launch unverifiable in the
Audit Manifest with a reason and propose Known Noise (goes to 26). Fixes
F587, ts3 coredumps.

**Blocked by:** 12

**Status:** ready-for-agent

- [ ] Root cause noted in Comments
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base)
