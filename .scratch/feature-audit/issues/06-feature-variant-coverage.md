# 06: Feature ↔ variant coverage

**What to build:** `check` fails with a Finding for any host option or
feature value that no Audit Variant enables, derived from the option
definitions (not a hand list), so new features cannot go unaudited.

**Blocked by:** 04

**Status:** done

- [x] Feature set derived from the installer's option sources
- [x] Unenabled feature → Finding naming it
- [x] `unverifiable` manifest entries satisfy coverage with a reason
- [x] Bats: fixture adds an option → gap Finding; drift guard in suite
