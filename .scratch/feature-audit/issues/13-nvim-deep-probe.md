# 13: nvim deep probe

**What to build:** nvim probe: every plugin spec loads, `:checkhealth`
clean, and for each language registry row (ADR 0141) LSP attaches,
formatter runs, DAP adapter starts on a sample file. nvim keymap parser
(headless dump) + binds file.

**Blocked by:** 11

**Status:** ready-for-agent

- [ ] Sample fixture file per registry language
- [ ] Plugin load / checkhealth / LSP / formatter / DAP each a check
- [ ] Keymap parser bats; every keymap has an expectation
- [ ] Passes offline or yields runtime-fetch Findings
