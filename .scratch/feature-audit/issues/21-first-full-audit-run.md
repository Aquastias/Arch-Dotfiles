# 21: First full Audit Run

**What to build:** one full Audit Run across every variant; the resulting
`findings.md` is handed to the fix session (fix all, then rerun until
clean). ADR 0152 status updated when clean.

**Blocked by:** 05, 06, 07, 10, 20

**Status:** ready-for-agent

- [ ] `check` clean before run
- [ ] Every variant attempted; fatal aborts recorded as Findings
- [ ] `findings.md` + `findings.jsonl` + raw logs + gallery produced
