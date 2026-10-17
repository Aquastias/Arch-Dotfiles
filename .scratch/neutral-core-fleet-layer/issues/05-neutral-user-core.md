# 05: Neutral User Core

**What to build:** a user created by anyone else gets no personal userland.
User Core becomes `/bin/bash`, generic groups, no programs; `aquastias` gains
today's User Core programs (order preserved for Program Dependency resolution)
and `/bin/zsh`. The throwaway VM users drop their now-vacuous exclusions. See
PRD and [[ADR 0157]].

**Blocked by:** 02 (Golden capture)

**Status:** ready-for-agent

- [ ] Golden test (02) passes unchanged for `desktop` and `laptop`
- [ ] A user with no User Profile programs resolves to no programs and bash
- [ ] VM users carry no `programs_exclude` of former core programs; VM
      fixtures resolve as before
- [ ] Root Shell behaviour unchanged for `desktop`/`laptop`
- [ ] CONTEXT.md User Core / Root Shell entries updated
