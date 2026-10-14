# 08: Contract: make the raw config read lint strict

**What to build:** with every batch migrated, the lint baseline is deleted
and any raw config read outside the Install Config Reader fails outright.
CONTEXT.md (Install Config Reader) describes binding; a new ADR records the
bind + schema-owns-all-defaults decision as extending ADR 0015. Decisions:
candidate #1, Q15–Q18.

**Blocked by:** 04, 05, 06, 07

**Status:** ready-for-agent

- [ ] Baseline deleted; lint strict
- [ ] CONTEXT.md Install Config Reader entry updated
- [ ] ADR recorded (extends 0015)
- [ ] Full suite + lints green

## Comments
