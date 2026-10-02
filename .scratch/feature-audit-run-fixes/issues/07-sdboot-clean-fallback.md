# 07: Clean systemd-boot fallback entries

**What to build:** Fallback image staging no longer leaks mkinitcpio output
into the loader entry; fallback entries are valid and boot. Fixes the logind
'Unknown line ==>/->/Secureboot' Findings.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] loader-entries.bats: noisy staging still yields a clean entry
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base)
