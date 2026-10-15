# 08: Contract: make the raw config read lint strict

**What to build:** with every batch migrated, the lint baseline is deleted
and any raw config read outside the Install Config Reader fails outright.
CONTEXT.md (Install Config Reader) describes binding; a new ADR records the
bind + schema-owns-all-defaults decision as extending ADR 0015. Decisions:
candidate #1, Q15–Q18.

**Blocked by:** 04, 05, 06, 07

**Status:** done

- [x] Baseline deleted; lint strict
- [x] CONTEXT.md Install Config Reader entry updated
- [x] ADR recorded (extends 0015)
- [x] Full suite + lints green

## Comments

2026-10-15: Baseline deleted; raw-config-reads.sh strict (`--update` gone,
each read reported as `raw config read: file:line: text`). CONTEXT.md:
Install Config Reader entry (+ Install Default / Guided Launch Preset from
02). ADR 0154 records bind + schema-owns-Install-Defaults + launch presets +
the lint, extending ADR 0015 (cross-linked).
