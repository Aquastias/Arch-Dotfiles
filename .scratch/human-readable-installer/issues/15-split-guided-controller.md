# 15: Split guided controller

**What to build:** The 4k-line guided controller becomes several files,
one responsibility each (e.g. field state, cycling, options, apply,
users/programs), each ≤ 500 lines with its Prefix Map entry. Pure move:
no renames, no logic change, so the diff is reviewable as relocation only.

**Blocked by:** 05 — Pilot

**Status:** done

- [x] Every resulting file ≤ 500 lines; Prefix Map updated (owner
      re-approval only for new public Prefixes)
- [x] Function bodies byte-identical to before (moved only)
- [x] shellcheck, bats, `audit.sh`, lint green
- [x] Guided-flow run green (local HEAD 620d2bb: single/guided --verify-boot, 2026-10-12)

## Comment

`controller-list.sh` is 652 lines: `guided_ctl_list` alone is 645 and a pure
move cannot split it — ticket 16 splits the function.
