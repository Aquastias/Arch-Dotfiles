# 22: Leftover tests + Baseline zero

**What to build:** Remaining test helpers and bats files follow the
Readability Rules, the Readability Baseline is empty and removed, and the lint
runs strict: any violation anywhere fails. ADR 0153 status → implemented.

**Blocked by:** 06–21 (every area ticket)

**Status:** done

- [x] Test helpers/bats renamed; `@test` titles left free text
- [x] Baseline removed; lint strict; suite green
- [x] Full VM install + guided-flow run green
- [x] ADR 0153 status updated

## Comments

2026-10-12: the first "green" VM checks (2026-10-11/12 matrix, guided,
arch-combined) installed the PUSHED GitHub repo (vm/lib/core.sh REPO_URL
default), not local HEAD — see .scratch/vm-local-repo-default. The base
Audit Run (which stages local HEAD) then caught two refactor regressions,
both fixed with regression tests:
- `lib/layout/state.sh` (ticket 06) was not staged into the chroot's
  /root/lib, so every desktop adapter died sourcing common.sh;
- a rename leaked into the zfs/btrfs rollback hooks' escaped guest variable
  (`\${mp}` → `\${mountpoint}`), so every rollback dataset mounted over
  /new_root and first boot had no /sbin/init (rename tool bug: it renamed
  escaped `\$var` in unquoted heredocs; fixed).
Re-verified on local HEAD 620d2bb: Audit Run base (all phases, 0 findings),
matrix zfs-single-plain and guided single/guided (install + boot verify).
