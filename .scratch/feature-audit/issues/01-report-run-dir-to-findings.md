# 01: `report`: run folder → Findings

**What to build:** `feature-audit report <run-dir>` turns a folder of raw
collected artifacts (install logs, journals, failed-unit lists, coredump
lists, kernel errors) into Findings (ADR 0152). Lines are classified,
committed Known Noise (empty) filters them, normalized keys (timestamps,
pids, addresses stripped) dedup across variants/boots with frequency counts,
and it writes an agent-ready `findings.md` + `findings.jsonl`. Exit non-zero
on any Finding. Pure: no VM. Establishes the entry point and its lib area.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Entry point with `report` subcommand + usage; lib area sourced by it
- [ ] Known Noise file committed (empty); entries = regex, optional
      scope (source/phase), reason/ADR
- [ ] Finding fields: id, key, variants, phase, source, program, adrs,
      excerpt, count/total, log paths, repro
- [ ] Same Finding in N variants → one entry listing variants
- [ ] Intermittent Finding shows frequency (e.g. 2/3)
- [ ] `findings.md` grouped by phase then source; `findings.jsonl` one per
      line
- [ ] Exit 0 on clean run dir, non-zero on any Finding
- [ ] Bats with fixture run folders cover all of the above; mirrors dir
      layout for Change-Targeted Runs
