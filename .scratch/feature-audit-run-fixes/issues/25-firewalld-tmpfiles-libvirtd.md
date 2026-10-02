# 25: firewalld iptables, tmpfiles-clean, libvirtd

**What to build:** Diagnose each on a held VM; fix, or propose Known Noise
with a reason (goes to 26).

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Root cause per item noted in Comments
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base)

## Comments

firewalld (docker stale chains), libvirtd udev/dmidecode, tmpfiles X-socket
locks: upstream/VM noise. laptop tmpfiles-clean failure was intermittent;
watch in the full run.
