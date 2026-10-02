# 04: Serial console for efistub/limine/refind

**What to build:** The VM seed injects console=ttyS0 for every bootloader, so
the Console Answerer sees and answers the ZFS unlock prompt. Fixes F258.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] seed-generator.bats: console=ttyS0 for each of the five loaders
- [ ] Re-checked with `run --variant`/`--reuse`; its Findings gone (efistub,
limine, refind)
