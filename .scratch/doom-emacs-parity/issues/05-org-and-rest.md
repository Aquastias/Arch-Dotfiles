# 05: Org and REST

**What to build:** Doom org and nvim's orgmode work on the same notes: same
org directory, agenda files and default refile file as nvim (ADR 0160). A
REST client on `SPC R s` (send) and `SPC R c` (copy as curl) via
`restclient`, recorded as a **loose match** — its format is close to, not
identical with, rest.nvim's `.http`.

**Blocked by:** 01 (Tracer).

**Status:** ready-for-agent

- [ ] `init.el` enables org; `config.el` sets nvim's org paths
- [ ] `packages.el` adds restclient; `SPC R s`/`SPC R c` bound
- [ ] Static bats: org paths match nvim's orgmode config; REST binds present
- [ ] VM: agenda lists a note from the shared org dir; a request in a
      sample file sends; noted in Comments
- [ ] `.http` format differences found are recorded for the ADR

## Comments
