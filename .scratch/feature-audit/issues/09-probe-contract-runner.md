# 09: Probe contract + runner

**What to build:** the probe contract added to the program spec: a
program may ship a guest-side probe script (prints `PASS|FAIL|SKIP
<check-id> <message>`, env gives user/session/phase/online) and a binds
file. A runner stages + runs every probe for every variant user and root,
collects output/stderr, and `report` turns FAIL lines and stderr into
Findings. `check` flags programs with no probe unless the manifest marks
them `unverifiable` (new manifest section). First probes: zsh, kitty.

**Blocked by:** 04

**Status:** done

- [x] Contract documented in the program spec
- [x] Probes run per user + root; tagged by program/user
- [x] FAIL / stderr → Findings; SKIP counted, not a Finding
- [x] Missing probe → `check` Finding; `unverifiable` requires reason
- [x] zsh + kitty probes pass on a real run
- [x] Bats: coverage gap + probe-output parsing via fixtures
