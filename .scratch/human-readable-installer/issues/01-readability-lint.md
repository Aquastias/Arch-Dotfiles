# 01: Readability Lint, Baseline, agent doc

**What to build:** The Readability Rules become enforced. A bash +
awk lint beside the no-python gate reports `rule: file:line: detail`
for: abbreviation tokens in function/local names (acronym allowlist,
`i`/`j`/`rc`), function length/nesting caps, file length cap, replace-tier
tools, `sed` without `-i`. A committed Readability Baseline (keys: rule +
file + symbol, no line numbers) holds today's violations; new ones fail,
stale entries fail. `docs/agents/readability.md` states the rules (ADR 0153)
and root `CLAUDE.md` points to it, cross-linked with Comment Style. Prefix
rule and doc-ADR-link rule come later (02, 04).

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Lint + bats test modelled on the no-python gate; headline "repo clean
      vs baseline" test plus fixture repos per rule (caught + allowed cases:
      acronyms, `i`/`j`/`rc`, `sed -i`, bats `@test` titles, jq `def`)
- [ ] New violation → fail; stale baseline entry → fail
- [ ] Baseline generated and committed; suite green
- [ ] Agent doc + `CLAUDE.md` pointer, 80-col
