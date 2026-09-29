# 10: Offline/online probes

**What to build:** VM Agent Control `net on|off` (guest link down/up via
libvirt). The probe phase runs offline first, then online; a check that
fails offline but passes online is a "runtime fetch" Finding.

**Blocked by:** 09

**Status:** ready-for-agent

- [ ] `net on|off` verb + pure-function bats
- [ ] Probe env exposes online state
- [ ] Offline-FAIL + online-PASS → runtime-fetch Finding (bats fixture)
- [ ] Network restored before later phases
