# 08: Reporter: one journal entry, one Finding

**What to build:** feature-audit.sh report folds continuation lines (stack
frames, wrapped text) into their head entry, normalises volatile tokens (hex
ids, PIDs, mount hashes, unit instance suffixes) in the dedup key, ignores
pacman 'up to date -- skipping', and gives every Finding a unique id,
zero-padded to the run's width, identical in findings.md and findings.jsonl
(today md reuses ids and F1000 prints as F000).

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] report.bats: stack trace = 1 Finding
- [ ] report.bats: N busy unmounts differing only by hash = 1 Finding
- [ ] report.bats: pacman up-to-date line is not a Finding
- [ ] report.bats: ids unique and equal across md/jsonl at 1000+ Findings
- [ ] Re-report of 20260929-200142 shows the reduced count
