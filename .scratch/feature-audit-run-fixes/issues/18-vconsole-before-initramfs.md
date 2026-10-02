# 18: vconsole.conf before the initramfs

**What to build:** vconsole.conf is written before mkinitcpio runs, so
sd-vconsole embeds it and systemd-vconsole-setup succeeds. Fixes F555 and
vconsole journal Findings.

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] Install log has no sd-vconsole 'not found' warning
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (base)

## Comments

Install warning is pacstrap's throwaway image (Known Noise). Boot failure on
greetd/pure: early KMS via the kms hook, except NVIDIA (31d2831, ef153af);
ADR 0043 amended.
