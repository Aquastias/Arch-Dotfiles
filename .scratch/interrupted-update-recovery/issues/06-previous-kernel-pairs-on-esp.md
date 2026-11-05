# 06: Previous kernel pairs on the ESP

Status: ready-for-agent

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** the ESP Kernel Sync keeps, for each selected kernel whose
version changes, the replaced kernel + default initramfs under stable
`-prev` names (no previous fallback). Unchanged kernels keep only their
current files. When the space preflight finds no room, the pair is skipped
with a warning and the transaction proceeds. The ESP budget for new
installs adds one previous pair (~100 MiB with the ZFS module) per selected
kernel. Amends ADR 0038 and ADR 0078.

**Blocked by:** 02.

- [ ] Bats: `-prev` pair only for changed kernels; strays never
- [ ] Bats: short ESP skips the pair with a warning, sync still succeeds
- [ ] Bats: budget grows per kernel
- [ ] Temp-then-rename and verification cover the previous pair
- [ ] Retrofit enables it
