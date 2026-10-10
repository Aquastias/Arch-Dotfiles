# 15: Split guided controller

**What to build:** The 4k-line guided controller becomes several files,
one responsibility each (e.g. field state, cycling, options, apply,
users/programs), each ≤ 500 lines with its Prefix Map entry. Pure move:
no renames, no logic change, so the diff is reviewable as relocation only.

**Blocked by:** 05 — Pilot

**Status:** ready-for-agent

- [ ] Every resulting file ≤ 500 lines; Prefix Map updated (owner
      re-approval only for new public Prefixes)
- [ ] Function bodies byte-identical to before (moved only)
- [ ] shellcheck, bats, `audit.sh`, lint green
- [ ] Guided-flow run (VM Agent Control) green
