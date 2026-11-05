# 06: Previous kernel pairs on the ESP

Status: done

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** the ESP Kernel Sync keeps, for each selected kernel whose
version changes, the replaced kernel + default initramfs under stable
`-prev` names (no previous fallback). Unchanged kernels keep only their
current files. When the space preflight finds no room, the pair is skipped
with a warning and the transaction proceeds. The ESP budget for new
installs adds one previous pair (~100 MiB with the ZFS module) per selected
kernel. Amends ADR 0038 and ADR 0078.

**Blocked by:** 02.

- [x] Bats: `-prev` pair only for changed kernels; strays never
- [x] Bats: short ESP skips the pair with a warning, sync still succeeds
- [x] Bats: budget grows per kernel
- [x] Temp-then-rename and verification cover the previous pair
- [x] Retrofit enables it

## Comments

- Implementation note: the previous pair is refreshed by a PreTransaction
  hook on every transaction, not by the kernel-only ESP Kernel Sync. A
  kernel-only refresh would leave `-prev` a version behind the newest Update
  Snapshot after a later non-kernel update, and Undo Last Update would boot a
  mismatched kernel. ADR 0166 item 4 updated. "Changed kernels" became "kernels
  whose `-prev` pair is missing or differs".
- Pinned ESP sizes are still validated without previous pairs (they are
  optional); only auto-size adds them.
