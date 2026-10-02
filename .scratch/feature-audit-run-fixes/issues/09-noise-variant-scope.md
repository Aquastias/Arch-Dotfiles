# 09: Variant-scoped Known Noise

**What to build:** Known Noise entries take an optional variants list; report
applies it, check validates it. Absent = global. Amends ADR 0152 (with 10).

**Blocked by:** None (can start immediately)

**Status:** done (pending the full Audit Run, ticket 27)

- [ ] report.bats: entry scoped to a variant mutes only there
- [ ] check.bats: bad variants value rejected; unknown variant id rejected

## Comments

Optional variants scope; check validates ids and regexes (4c3b71d); array
regexes for 80 cols (9ff2684).
