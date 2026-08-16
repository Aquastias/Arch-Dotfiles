# 03 — cups leaves the Packages system-programs picker

**What to build:** Make the Printing toggle cups's **sole** menu home. cups is no
longer offered as a selectable row in the Guided Installer's Packages →
system-programs picker, so there is no double representation and no way to reach
cups except the Printing service toggle. The filter is scoped to the
toggle-owned program only — other System Programs (grub, sops) are untouched.

**Blocked by:** 01 — Toggle-derived cups (cups is toggle-owned only after that
slice removes it from Host Core and the toggle drives it).

**Status:** ready-for-agent

- [x] `cups` does not appear in the Packages → system-programs picker list.
- [x] Other system programs (grub, sops) still appear and are selectable as
      before.
- [x] The filter keys on the toggle-owned program set, not a hard-coded `cups`
      string check that would silently miss a future toggle-owned program.
- [x] Tests extend the guided-packages bats: cups absent from the picker list,
      other system programs still present.
