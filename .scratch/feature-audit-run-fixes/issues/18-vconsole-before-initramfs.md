# 18: vconsole.conf before the initramfs

**What to build:** vconsole.conf is written before mkinitcpio runs, so
sd-vconsole embeds it and systemd-vconsole-setup succeeds. Fixes F555 and
vconsole journal Findings.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Install log has no sd-vconsole 'not found' warning
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base)
