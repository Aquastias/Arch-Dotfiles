# 06: Feature ↔ variant coverage

**What to build:** `check` fails with a Finding for any host option or
feature value that no Audit Variant enables, derived from the option
definitions (not a hand list), so new features cannot go unaudited.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Feature set derived from the installer's option sources
- [ ] Unenabled feature → Finding naming it
- [ ] `unverifiable` manifest entries satisfy coverage with a reason
- [ ] Bats: fixture adds an option → gap Finding; drift guard in suite
