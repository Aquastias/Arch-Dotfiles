# 09: Probe contract + runner

**What to build:** the probe contract added to the program spec: a
program may ship a guest-side probe script (prints `PASS|FAIL|SKIP
<check-id> <message>`, env gives user/session/phase/online) and a binds
file. A runner stages + runs every probe for every variant user and root,
collects output/stderr, and `report` turns FAIL lines and stderr into
Findings. `check` flags programs with no probe unless the manifest marks
them `unverifiable` (new manifest section). First probes: zsh, kitty.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Contract documented in the program spec
- [ ] Probes run per user + root; tagged by program/user
- [ ] FAIL / stderr → Findings; SKIP counted, not a Finding
- [ ] Missing probe → `check` Finding; `unverifiable` requires reason
- [ ] zsh + kitty probes pass on a real run
- [ ] Bats: coverage gap + probe-output parsing via fixtures
