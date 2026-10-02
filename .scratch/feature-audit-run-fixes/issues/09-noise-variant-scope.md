# 09: Variant-scoped Known Noise

**What to build:** Known Noise entries take an optional variants list; report
applies it, check validates it. Absent = global. Amends ADR 0152 (with 10).

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] report.bats: entry scoped to a variant mutes only there
- [ ] check.bats: bad variants value rejected; unknown variant id rejected
