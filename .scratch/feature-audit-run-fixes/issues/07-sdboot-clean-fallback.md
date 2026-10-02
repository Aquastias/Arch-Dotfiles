# 07: Clean systemd-boot fallback entries

**What to build:** Fallback image staging no longer leaks mkinitcpio output
into the loader entry; fallback entries are valid and boot. Fixes the logind
'Unknown line ==>/->/Secureboot' Findings.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] loader-entries.bats: noisy staging still yields a clean entry
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base)

## Comments

mkinitcpio stdout leaked into the captured fallback name; staging extracted
to lib/boot/esp-stage.sh (02c769b).
