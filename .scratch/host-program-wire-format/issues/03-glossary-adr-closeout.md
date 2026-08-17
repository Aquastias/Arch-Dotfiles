# 03 — Glossary + ADR closeout

**What to build:** Close the loop opened by ADR 0084. The [[Host Program]]
glossary entry now states the host declares its programs in `host_programs`
(the deferral is resolved, not pending), and no stray `system_programs` remains
in the glossary prose. A new ADR records the two decisions this migration
encoded — the `kind: host|user` enum over a `host` bool, and the no-alias hard
cutover enforced by the closed schema — and marks ADR 0084's deferral resolved.
Historical ADRs stay verbatim.

**Blocked by:** 01, 02 — the glossary and ADR describe the completed wire-format
migration, so both renames must have landed.

**Status:** ready-for-agent

- [ ] The Host Program glossary entry states the field is `host_programs` with
      the deferral resolved; no `system_programs` mention remains in the
      glossary.
- [ ] A new ADR records the `kind` enum choice and the no-alias hard cutover,
      and marks ADR 0084's deferral resolved.
- [ ] Historical ADRs (0079, 0080, 0084, …) are unchanged.
