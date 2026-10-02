# 21: First full Audit Run

**What to build:** one full Audit Run across every variant; the resulting
`findings.md` is handed to the fix session (fix all, then rerun until
clean). ADR 0152 status updated when clean.

**Blocked by:** 05, 06, 07, 10, 20

**Status:** done

- [x] `check` clean before run
- [x] Every variant attempted; fatal aborts recorded as Findings
- [x] `findings.md` + `findings.jsonl` + raw logs + gallery produced

## Comments

- First full run started after the tool landed (all 18 variants, `--keep`).
- Completed 2026-10-01: all 18 variants attempted, 1086 raw Findings in
  `.installer/.audit-runs/20260929-200142/findings.md` (gitignored).
