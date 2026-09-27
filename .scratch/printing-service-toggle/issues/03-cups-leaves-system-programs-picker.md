# 03 — cups leaves the Packages system-programs picker

**What to build:** Make the Printing toggle cups's **sole** menu home. cups is no
longer offered as a selectable row in the Guided Installer's Packages →
system-programs picker, so there is no double representation and no way to reach
cups except the Printing service toggle. The filter is scoped to the
toggle-owned program only — other System Programs (grub, sops) are untouched.

**Blocked by:** 01 — Toggle-derived cups (cups is toggle-owned only after that
slice removes it from Host Core and the toggle drives it).

**Status:** done

- [x] `cups` does not appear in the Packages → system-programs picker list.
- [x] Other system programs (grub, sops) still appear and are selectable as
      before.
- [x] The filter keys on the toggle-owned program set, not a hard-coded `cups`
      string check that would silently miss a future toggle-owned program.
- [x] Tests extend the guided-packages bats: cups absent from the picker list,
      other system programs still present.

## Comments

- 2026-09-27 audit: fa4b5ed (config/printing.bats, guided-menu.bats,
  resolver/explain-packages bats), ab99513 (docs). Later: own category merged
  into Daemons (ADR 0081); system_programs → host_programs (ADR 0085); Packages
  picker replaced by Menu-Owned filtering (ADR 0086).
